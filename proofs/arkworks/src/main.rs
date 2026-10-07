//! Runs the unrelated-board demonstration with KZG and IPA.

use ark_bls12_381::Fr;
use ark_poly::univariate::DensePolynomial;
use ark_poly_commit::PolynomialCommitment;
use rand::rngs::OsRng;
use tic_tac_toe_proof_boundary::{Board, Ipa, Kzg, Player, ProofContext};

fn demonstrate<S: PolynomialCommitment<Fr, DensePolynomial<Fr>>>(
    name: &str,
) -> Result<(), Box<dyn std::error::Error>>
where
    S::Error: 'static,
{
    let mut rng = OsRng;
    let context = ProofContext::<S>::setup(&mut rng)?;
    let player = Player::new(0)?;
    let current = Board::new([0, 1, 2, 2, 2, 2, 2, 2, 2])?;
    let unrelated = Board::new([0, 0, 0, 1, 1, 2, 2, 2, 2])?;
    let current_game = context.game_context(current, player)?;
    let winning_game = context.game_context(unrelated, player)?;
    let proof = context.prove(unrelated, player, &mut rng)?;
    let detector = context.verify_detector(&proof)?;
    let bound_current = context.verify_bound(&proof, &current_game)?;
    let bound_winning = context.verify_bound(&proof, &winning_game)?;
    println!(
        "{name}: unrelated winning board, detector={detector}, bound_current={bound_current}, bound_matching={bound_winning}"
    );
    if !detector || bound_current || !bound_winning {
        return Err(std::io::Error::other(
            "demonstration produced an unexpected verification result",
        )
        .into());
    }
    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!(
        "Public-board evaluation proofs; development parameters; no circuit SNARK or legal-history proof."
    );
    demonstrate::<Kzg>("KZG")?;
    demonstrate::<Ipa>("IPA")?;
    Ok(())
}
