use crate::{Board, Error, Player};
use ark_bls12_381::{Bls12_381, Fr, G1Affine};
use ark_crypto_primitives::sponge::merlin::Transcript;
use ark_poly::{
    EvaluationDomain, Evaluations, Radix2EvaluationDomain, univariate::DensePolynomial,
};
use ark_poly_commit::{
    LabeledCommitment, LabeledPolynomial, PolynomialCommitment, ipa_pc::InnerProductArgPC,
    marlin_pc::MarlinKZG10,
};
use ark_serialize::CanonicalSerialize;
use blake2::Blake2s256;
use rand::{CryptoRng, RngCore};

const LABEL: &str = "tic-tac-toe-board-v1";
const TRANSCRIPT: &[u8] = b"tic-tac-toe-board-opening-v1";
const DOMAIN_SIZE: usize = 16;
const DEGREE: usize = DOMAIN_SIZE - 1;
type Polynomial = DensePolynomial<Fr>;
type Domain = Radix2EvaluationDomain<Fr>;

/// Arkworks' Marlin KZG commitment backend over BLS12-381.
pub type Kzg = MarlinKZG10<Bls12_381, Polynomial>;
/// Arkworks' inner-product commitment backend over BLS12-381 G1.
pub type Ipa = InnerProductArgPC<G1Affine, Blake2s256, Polynomial>;

/// A submitted public board, player, commitment and nine evaluation proofs.
///
/// Parameters are owned by the verifier, never supplied in this object.
pub struct BoardProof<S: PolynomialCommitment<Fr, Polynomial>> {
    board: Board,
    player: Player,
    commitment: S::Commitment,
    openings: Vec<S::Proof>,
}

/// The expected board commitment and player, supplied from trusted game state.
///
/// This value does not authenticate its source or prove legal history.
pub struct GameContext<S: PolynomialCommitment<Fr, Polynomial>> {
    commitment: S::Commitment,
    player: Player,
}

/// Development parameters for one commitment backend.
///
/// Local KZG setup has no ceremony provenance. No setup secrets are exported.
pub struct ProofContext<S: PolynomialCommitment<Fr, Polynomial>> {
    committer: S::CommitterKey,
    verifier: S::VerifierKey,
    domain: Domain,
}

impl<S: PolynomialCommitment<Fr, Polynomial>> ProofContext<S>
where
    S::Error: 'static,
{
    /// Generates bounded development parameters using a cryptographic RNG.
    ///
    /// # Errors
    /// Returns a backend error for setup/trim failures or a domain error.
    pub fn setup(rng: &mut (impl RngCore + CryptoRng)) -> Result<Self, Error> {
        let domain = Domain::new(DOMAIN_SIZE).ok_or(Error::DomainUnavailable)?;
        let parameters = S::setup(DEGREE, None, rng).map_err(Error::backend)?;
        let (committer, verifier) =
            S::trim(&parameters, DEGREE, 0, None).map_err(Error::backend)?;
        Ok(Self {
            committer,
            verifier,
            domain,
        })
    }

    fn polynomial(&self, board: Board) -> LabeledPolynomial<Fr, Polynomial> {
        let mut values = vec![Fr::from(0u64); DOMAIN_SIZE];
        for (value, &cell) in values.iter_mut().zip(board.cells()) {
            *value = Fr::from(cell);
        }
        let polynomial = Evaluations::from_vec_and_domain(values, self.domain).interpolate();
        LabeledPolynomial::new(LABEL.to_owned(), polynomial, None, None)
    }

    /// Commits a verifier-owned board and expected player without hiding.
    ///
    /// The caller must obtain the board/player from authenticated game state.
    /// # Errors
    /// Returns backend errors or an unexpected commitment count.
    pub fn game_context(&self, board: Board, player: Player) -> Result<GameContext<S>, Error> {
        let polynomial = self.polynomial(board);
        let (mut commitments, _) =
            S::commit(&self.committer, [&polynomial], None).map_err(Error::backend)?;
        if commitments.len() != 1 {
            return Err(Error::InvalidAssembly);
        }
        let commitment = commitments.remove(0).commitment().clone();
        Ok(GameContext { commitment, player })
    }

    /// Produces real evaluation proofs for all nine disclosed board cells.
    ///
    /// A losing or unreachable board may also have valid evaluation proofs.
    /// # Errors
    /// Returns backend, serialisation or assembly errors.
    pub fn prove(
        &self,
        board: Board,
        player: Player,
        rng: &mut (impl RngCore + CryptoRng),
    ) -> Result<BoardProof<S>, Error> {
        let polynomial = self.polynomial(board);
        let (commitments, states) =
            S::commit(&self.committer, [&polynomial], None).map_err(Error::backend)?;
        if commitments.len() != 1 || states.len() != 1 {
            return Err(Error::InvalidAssembly);
        }
        let commitment = commitments[0].commitment().clone();
        let mut openings = Vec::with_capacity(9);
        for (index, point) in self.domain.elements().take(9).enumerate() {
            let mut transcript = transcript::<S>(&commitment, player, index)?;
            openings.push(
                S::open(
                    &self.committer,
                    [&polynomial],
                    &commitments,
                    &point,
                    &mut transcript,
                    &states,
                    Some(rng),
                )
                .map_err(Error::backend)?,
            );
        }
        Ok(BoardProof {
            board,
            player,
            commitment,
            openings,
        })
    }

    /// Checks all evaluations and the native winning-line predicate.
    ///
    /// This deliberately limited verifier does not bind to a trusted game.
    /// Returns false for a losing board, missing proof or rejected opening.
    /// # Errors
    /// Returns backend or commitment serialisation errors.
    pub fn verify_detector(&self, proof: &BoardProof<S>) -> Result<bool, Error> {
        if proof.openings.len() != 9 || !proof.board.wins(proof.player) {
            return Ok(false);
        }
        let labelled = LabeledCommitment::new(LABEL.to_owned(), proof.commitment.clone(), None);
        for (index, point) in self.domain.elements().take(9).enumerate() {
            let mut transcript = transcript::<S>(&proof.commitment, proof.player, index)?;
            if !S::check(
                &self.verifier,
                [&labelled],
                &point,
                [Fr::from(proof.board.cells()[index])],
                &proof.openings[index],
                &mut transcript,
                None,
            )
            .map_err(Error::backend)?
            {
                return Ok(false);
            }
        }
        Ok(true)
    }

    /// Requires detector acceptance plus the expected game board and player.
    ///
    /// Does not prove the game context is authentic, current or legally reached.
    /// # Errors
    /// Returns backend or canonical serialisation errors.
    pub fn verify_bound(
        &self,
        proof: &BoardProof<S>,
        game: &GameContext<S>,
    ) -> Result<bool, Error> {
        if proof.player != game.player || encode(&proof.commitment)? != encode(&game.commitment)? {
            return Ok(false);
        }
        self.verify_detector(proof)
    }
}

fn encode(value: &impl CanonicalSerialize) -> Result<Vec<u8>, Error> {
    let mut bytes = Vec::new();
    value
        .serialize_compressed(&mut bytes)
        .map_err(Error::Serialisation)?;
    Ok(bytes)
}

fn transcript<S: PolynomialCommitment<Fr, Polynomial>>(
    commitment: &S::Commitment,
    player: Player,
    index: usize,
) -> Result<Transcript, Error> {
    let mut transcript = Transcript::new(TRANSCRIPT);
    transcript.append_message(b"commitment", &encode(commitment)?);
    transcript.append_message(b"player", &[player.marker()]);
    transcript.append_message(b"cell-index", &(index as u64).to_le_bytes());
    Ok(transcript)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rand::SeedableRng;
    use rand_chacha::ChaCha20Rng;

    fn adversarial_checks<S: PolynomialCommitment<Fr, Polynomial>>() -> Result<(), Error>
    where
        S::Error: 'static,
    {
        let mut rng = ChaCha20Rng::from_seed([17; 32]);
        let context = ProofContext::<S>::setup(&mut rng)?;
        let player = Player::new(0)?;
        let winning = Board::new([0, 0, 0, 1, 1, 2, 2, 2, 2])?;
        let game = context.game_context(winning, player)?;
        let mut proof = context.prove(winning, player, &mut rng)?;
        proof.board = Board::new([0, 0, 0, 1, 2, 2, 2, 2, 2])?;
        assert!(
            !context.verify_detector(&proof)?,
            "a changed non-winning-line cell must fail"
        );
        proof.board = winning;
        proof.openings.swap(0, 3);
        assert!(
            !context.verify_detector(&proof)?,
            "proofs cannot move between cells"
        );
        proof.openings.swap(0, 3);
        proof.openings.push(proof.openings[0].clone());
        assert!(
            !context.verify_detector(&proof)?,
            "extra openings must fail closed"
        );
        proof.openings.pop();
        proof.openings.pop();
        assert!(
            !context.verify_detector(&proof)?,
            "missing openings must fail closed"
        );
        proof = context.prove(winning, player, &mut rng)?;
        let other = context.game_context(Board::new([0, 0, 0, 1, 2, 1, 2, 2, 2])?, player)?;
        proof.commitment = other.commitment;
        assert!(
            !context.verify_detector(&proof)?,
            "changed commitment must fail"
        );
        proof = context.prove(winning, player, &mut rng)?;
        let wrong_player = context.game_context(winning, Player::new(1)?)?;
        assert!(
            !context.verify_bound(&proof, &wrong_player)?,
            "trusted player must match"
        );
        assert!(context.verify_bound(&proof, &game)?);
        let dual_winner = Board::new([0, 0, 0, 1, 1, 1, 2, 2, 2])?;
        let mut changed_player = context.prove(dual_winner, player, &mut rng)?;
        changed_player.player = Player::new(1)?;
        assert!(dual_winner.wins(changed_player.player));
        assert!(
            !context.verify_detector(&changed_player)?,
            "changing a public player must invalidate the transcript even when both players have lines"
        );
        let losing = Board::new([0, 1, 2, 2, 2, 2, 2, 2, 2])?;
        let proof = context.prove(losing, player, &mut rng)?;
        assert!(
            !context.verify_detector(&proof)?,
            "openings alone do not imply a win"
        );
        Ok(())
    }

    #[test]
    fn kzg_rejects_a_proof_from_other_setup_parameters() -> Result<(), Error> {
        let mut rng = ChaCha20Rng::from_seed([53; 32]);
        let verifier = ProofContext::<Kzg>::setup(&mut rng)?;
        let other = ProofContext::<Kzg>::setup(&mut rng)?;
        let board = Board::new([0, 0, 0, 1, 1, 2, 2, 2, 2])?;
        let proof = other.prove(board, Player::new(0)?, &mut rng)?;
        assert!(!verifier.verify_detector(&proof)?);
        Ok(())
    }

    #[test]
    fn kzg_rejects_tampering() -> Result<(), Error> {
        adversarial_checks::<Kzg>()
    }
    #[test]
    fn ipa_rejects_tampering() -> Result<(), Error> {
        adversarial_checks::<Ipa>()
    }
}
