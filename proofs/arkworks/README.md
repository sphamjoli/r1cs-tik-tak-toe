# Tic-tac-toe proof boundary with KZG and IPA

A real proof can check while referring to the wrong board. This subproject opens a committed winning board with two Arkworks backends, then contrasts detector acceptance with a check against verifier-owned game state.

The existing project uses Circom, Groth16 and Solidity, with a separate Lean theorem for the detector. This Rust subproject demonstrates the omitted board relationship without changing that implementation. It uses BLS12-381 rather than the circuit's BN254 field; its commitment proofs cannot be submitted to the Solidity Groth16 verifier.

## Run the demonstration

Rust 1.97 or later is required. The subproject has been tested with Rust/Cargo 1.97.1. All directly used Arkworks crates are pinned to 0.6.0. `Cargo.lock` records the complete dependency resolution. All core Arkworks protocol crates resolve to 0.6.0; the upstream crypto-primitives macro crate remains at its separately versioned 0.5.0.

From the repository root:

```sh
cargo run --locked --manifest-path proofs/arkworks/Cargo.toml
cargo test --locked --manifest-path proofs/arkworks/Cargo.toml
```

After dependencies are cached, add `--offline` for a reproducible run without downloads. The demonstration returns a non-zero exit status if its expected acceptance/rejection pattern changes.

Both KZG and IPA should report:

```text
unrelated winning board, detector=true, bound_current=false, bound_matching=true
```

KZG means Kate–Zaverucha–Goldberg polynomial commitment. IPA means inner-product argument. These are distinct cryptographic backends; they do not verify one another.

## The two boards and the missing condition

Player 0 is X, player 1 is O, and 2 is empty. The trusted current board is:

```text
X O .
. . .
. . .
```

The submitted board is:

```text
X X X
O O .
. . .
```

The submitted board has a genuine winning line. It can arise from alternating moves: X at 0, O at 3, X at 1, O at 4, X at 2. The example therefore does not depend on an impossible board or a forged opening. It omits the connection to the board the current game actually records.

A commitment is a cryptographic representation of a polynomial. An opening supplies an evaluation value and evidence that it belongs to that commitment. Here, the polynomial interpolates the nine board cells on the first nine points of a sixteen-point FFT domain; the remaining seven honest-encoding values are zero. The public board and every opening are checked. The winning-line predicate runs in Rust on the disclosed board.

`verify_detector` requires nine accepted openings and a winning line for the submitted player. `verify_bound` also requires the submitted commitment and player to equal the expected commitment and player generated from trusted game state. Prover-selected keys and game context are never included in the submitted proof.

The additional check establishes board/player correspondence under the supplied parameters and cryptographic assumptions. The caller must authenticate the expected state and decide whether it is current and legally reached. A board-only context cannot distinguish different games with identical boards and players.

## Scope of the result

This is a public-board evaluation-proof demonstration, not a circuit SNARK or a zero-knowledge proof. It proves no hidden winning-line relation: all nine evaluations are opened and the relation is checked natively. The Rust implementation is tested, not formally proved. The [existing Lean theorem](../lean/README.md) remains a separate result about the manually translated circuit constraints.

KZG setup uses fresh OS randomness in the executable, but a local setup is not an independently secured ceremony. Test randomness is deterministic and used only for tests. Commitments use no hiding. IPA uses the upstream discrete-logarithm-based commitment implementation. Merlin transcript messages include a versioned purpose, canonical commitment, player and cell index; verifier-derived points and labels are fixed. Strict per-polynomial degree bounds are not annotated or claimed for fixed-point IPA queries.

The implementation supplies no parser, persistence, deployment, replay protection, authenticated history, escrow verification, compiler proof or cryptographic security reduction. It uses upstream cryptographic primitives rather than implementing them. Upstream Arkworks describes its commitment library as an academic prototype.

## Validation and dependency status

Run `bash proofs/arkworks/check.sh` after fetching the locked dependencies. It checks formatting, Clippy, tests and Rustdoc with warnings denied. The suite includes five unit tests, two real-backend integration tests and one doctest. The native detector is checked against a separately structured oracle for all 39,366 board/player combinations. Removing the commitment comparison causes both game-binding regressions to fail.

The dependency advisory command is `cargo deny --manifest-path proofs/arkworks/Cargo.toml check advisories`. It reports [RUSTSEC-2024-0388](https://rustsec.org/advisories/RUSTSEC-2024-0388) for Arkworks' transitive dependency on unmaintained `derivative` 2.2.0. No safe upgrade is listed. The advisory check remains failing, with no suppression. This development demonstration has no production security assurance.

## Sources

- [Arkworks 0.6.0 source and polynomial-commitment interface](https://docs.rs/ark-poly-commit/0.6.0/ark_poly_commit/). Documents the backends and shared interface used here.
- Kate, Zaverucha and Goldberg, [Polynomial Commitments](https://cacr.uwaterloo.ca/techreports/2010/cacr2010-10.pdf), 2010. Defines the KZG construction; the conference version is [Constant-Size Commitments to Polynomials and Their Applications](https://doi.org/10.1007/978-3-642-17373-8_11). This project uses Arkworks' Marlin variant.
- Bünz, Chiesa, Mishra and Spooner, [Proof-Carrying Data from Accumulation Schemes](https://eprint.iacr.org/2020/499), 2020. The protocol referenced by Arkworks' IPA implementation.
- [Existing Circom detector](../../circuits/tic_tak_toe.circom) and [Lean evidence boundary](../lean/README.md). These define the repository's board encoding and distinguish detector behaviour from protocol settlement.
