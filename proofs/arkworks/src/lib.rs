//! Public-board opening proofs and an explicit trusted-game binding.
//!
//! KZG and IPA attest polynomial evaluations. The win predicate is checked in
//! Rust on all nine disclosed cells; this crate supplies no circuit SNARK.

mod board;
mod error;
mod proof;

pub use board::{Board, Player};
pub use error::Error;
pub use proof::{BoardProof, GameContext, Ipa, Kzg, ProofContext};
