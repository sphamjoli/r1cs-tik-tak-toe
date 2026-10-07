//! Real-backend checks of the omitted relationship and repaired verifier.

use ark_bls12_381::Fr;
use ark_poly::univariate::DensePolynomial;
use ark_poly_commit::PolynomialCommitment;
use rand::SeedableRng;
use rand_chacha::ChaCha20Rng;
use tic_tac_toe_proof_boundary::{Board, Error, Ipa, Kzg, Player, ProofContext};

fn unrelated_board<S: PolynomialCommitment<Fr, DensePolynomial<Fr>>>() -> Result<(), Error>
where
    S::Error: 'static,
{
    let mut rng = ChaCha20Rng::from_seed([42; 32]);
    let context = ProofContext::<S>::setup(&mut rng)?;
    let player = Player::new(0)?;
    let current = Board::new([0, 1, 2, 2, 2, 2, 2, 2, 2])?;
    let unrelated = Board::new([0, 0, 0, 1, 1, 2, 2, 2, 2])?;
    let proof = context.prove(unrelated, player, &mut rng)?;
    let game = context.game_context(current, player)?;
    assert!(
        context.verify_detector(&proof)?,
        "the supplied board really has a line"
    );
    assert!(
        !context.verify_bound(&proof, &game)?,
        "a valid unrelated board must not settle this game"
    );
    let matching = context.game_context(unrelated, player)?;
    assert!(
        context.verify_bound(&proof, &matching)?,
        "binding must retain the genuine matching case"
    );
    Ok(())
}

#[test]
fn kzg_exposes_missing_game_binding() -> Result<(), Error> {
    unrelated_board::<Kzg>()
}

#[test]
fn ipa_exposes_missing_game_binding() -> Result<(), Error> {
    unrelated_board::<Ipa>()
}
