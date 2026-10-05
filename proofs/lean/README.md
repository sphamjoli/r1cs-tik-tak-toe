# Circuit soundness in Lean

If a board and its auxiliary values satisfy the tic-tac-toe circuit's equations, the output is one exactly when the chosen player fills a row, column or diagonal. Otherwise, the output is zero. Auxiliary values cannot make a non-winning board report a win. The theorem covers every satisfying assignment, including assignments not produced by the witness calculator.

## Symbolic statement

Let $F$ be a field of characteristic $q > 8$, $w$ a witness assignment, $B_w$ its board and $p_w$ its player. Let $L$ contain the three rows, three columns and two diagonals of the $3 \times 3$ board. Define

$$
\operatorname{Wins}(w) \;\equiv\;
\exists \ell \in L,\; \forall (i,j) \in \ell,\; B_w(i,j)=p_w.
$$

With $C(w)$ denoting the modelled circuit constraints, the theorem is

$$
\forall w,\quad C(w) \Longrightarrow
h_w=\begin{cases}
1 & \text{if }\operatorname{Wins}(w),\\
0 & \text{otherwise},
\end{cases}
$$

where $h_w$ is `has_won`. The field elements $0$ and $1$ are distinct. Consequently, $C(w)$ implies $h_w=1 \iff \operatorname{Wins}(w)$.

The corresponding declaration in [Soundness.lean](TicTacToe/Soundness.lean) is:

```lean
theorem circuit_soundness (q : ℕ) [CharP F q] (hq : 8 < q)
    (w : Witness F) (h : Constraints w) :
    w.hasWon = if Wins w then 1 else 0
```

`F` has a `Field` instance. `CharP F q` specifies its characteristic; `hq` states the bound. `w` contains the input, output and auxiliary signals. `h` supplies a proof that their polynomial equations hold. The conclusion determines the output from the board and player alone.

## Purpose and system boundary

The question is whether a prover can exploit the circuit's auxiliary values to claim a winning line that the board does not contain. Lean proves that no such assignment satisfies the modelled equations. This establishes the detector's arithmetic behaviour, one obligation within the game verification system.

Circom source is manually translated into the Lean constraint model, whose theorem is checked by the kernel. Separately, the compiler produces R1CS constraints used by Groth16; the contract then checks the public signals before settlement. Correct settlement depends on both paths and their connections. A theorem about the detector alone cannot establish that a contract verified the right board or paid the right player.

For example, an all-empty board with player zero has output zero. That is a correct detector result and can have a valid Groth16 proof. The contract must reject it as a winning claim. Conversely, a board with a complete row for player zero has output one, but the detector does not establish whether that board arose through authorised turns. The contract must authenticate that history and bind the proof's public signals to it.

| Question                                                                 | Evidence supplied                                                                             | Remaining obligation                                           |
| ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| Can auxiliary signals misreport a winning line?                          | Lean proves the output for every satisfying assignment of the model                           | Review source-to-model correspondence                          |
| Does the recorded circuit behave like the specification on board inputs? | Exhaustive compiled-R1CS checks over the ternary board and binary player domains              | Compiler correctness is not formally proved                    |
| Does a winning claim refer to the current game?                          | Contract checks output, board and player; integration tests exercise acceptance and rejection | Contract and verifier correctness are outside the Lean theorem |
| Does the game obey turn and payment rules?                               | Contract regression and stateful accounting tests                                             | No formal protocol or escrow theorem is supplied here          |

The boundary follows the distinction between a model and the larger system it represents. Meadows discusses how boundaries depend on the question being investigated and why relationships between components must remain visible (_Thinking in Systems: A Primer_, Chapter 4, “Why Systems Surprise Us”, and Chapter 7, “Living in a World of Systems”). Applied here, the detector is modelled precisely while its compiler, proof protocol and contract connections are stated separately. This framing guides the explanation; it is not evidence for the mathematical theorem.

## Constraint model and proof

[Constraints.lean](TicTacToe/Constraints.lean) models the equations of [`TikTakToe(3)`](../../circuits/tic_tak_toe.circom), with signal aliases substituted into their definitions. The proof proceeds through four steps:

1. Boolean equations constrain the player to $\{0,1\}$. Two boolean bits and their exclusion equation constrain each board cell to $\{0,1,2\}$, where two represents an empty cell.
2. Both `IsZero` equations determine each equality indicator, even when its inverse signal is arbitrary. A line-product recurrence therefore yields one exactly when all three cells match the player.
3. The accumulator equals the field reduction of the integer number of matching lines. This count lies between zero and eight. Since $q>8$, a positive count cannot become zero after reduction.
4. The final zero test and output equation determine $h_w$ from that count.

| Declaration                                          | Result                                                             |
| ---------------------------------------------------- | ------------------------------------------------------------------ |
| `player_domain`, `cell_domain`                       | Input values have the required domains                             |
| `isZero_sound`, `equality_sound`                     | Equality flags agree with field equality                           |
| `line_sound`, `accumulator_sound`                    | Line products and their sum agree with the geometric specification |
| `circuit_soundness`, `winning_iff`, `output_boolean` | The output is the Boolean win indicator                            |
| `bn254_soundness`                                    | The same result for the recorded BN254 scalar characteristic       |
| `winning_satisfiable`, `nonwinning_satisfiable`      | Both output values occur in satisfying assignments                 |

[Examples.lean](TicTacToe/Examples.lean) constructs an all-zero board for player zero and an all-empty board for player zero, including every auxiliary signal. These witnesses establish that the constraint relation is satisfiable for both outcomes under the theorem's field assumptions. They concern the detector; an all-zero board is not a legal alternating game history.

`bn254_soundness` checks that the recorded scalar modulus exceeds eight. It assumes a field instance of that characteristic; primality of the modulus and finite-field implementation correctness are not established by this declaration.

## Reproduce the checks

Use Bun 1.3.5, Node.js for the Hardhat/snarkjs tools, and [elan](https://leanprover-community.github.io/get_started.html). [lean-toolchain](lean-toolchain) pins Lean 4.19.0; [lakefile.toml](lakefile.toml) and [lake-manifest.json](lake-manifest.json) pin mathlib v4.19.0 and its dependency revisions. From the repository root:

```sh
bun install --frozen-lockfile
bun proofs/lean/check.cjs --setup
bun run test:formal
```

The setup command resolves the dependencies and downloads compiled mathlib modules before building. Subsequent checks use the installed dependencies. Direct theorem inspection is available with:

```sh
cd proofs/lean
lake build
lake env lean AxiomAudit.lean
```

[check.cjs](check.cjs) verifies the recorded source hashes, rejects proof placeholders and added axioms, builds the library and audits the principal theorems. [AxiomAudit.lean](AxiomAudit.lean) prints their dependencies. Only `propext`, `Classical.choice` and `Quot.sound` are accepted; an unexpected dependency or missing audit fails the command. Lean's kernel checks the proof terms without native decision evaluation.

## Evidence boundary

[source-manifest.json](source-manifest.json) records SHA-256 hashes of the circuit and circomlib 2.0.5's equality, zero-test and bit-decomposition sources. Their upstream equations are in [comparators.circom](https://github.com/iden3/circomlib/blob/v2.0.5/circuits/comparators.circom) and [bitify.circom](https://github.com/iden3/circomlib/blob/v2.0.5/circuits/bitify.circom). A changed source fails the check until its correspondence with the Lean model is reviewed and the manifest is deliberately updated.

Source-to-model correspondence is manually reviewed. Hashes identify the reviewed files; they do not prove the translation correct. The formal result establishes the mathematical model's soundness under its field assumptions. Compiler correctness, R1CS transformation, Groth16 assumptions, setup integrity, Solidity verification and legal-play or escrow rules remain outside this theorem. Board and player inputs are public.

`bun run test:soundness` complements the theorem with exhaustive checks of 39,366 board/player combinations against the compiled R1CS, flipped-output rejection and invalid-input checks. The [game contract](../../src/TikTakToeGame.sol) separately requires output one and binds the board and player to authenticated game state. Its integration and accounting checks are documented in the [repository README](../../README.md).

## Commit checks

Lefthook runs `bun run check:lean`'s checker before every commit. The check verifies the reviewed source hashes, builds all proof modules with warnings treated as errors, and audits the principal theorem dependencies. Decorative comments are checked across repository-owned files, including Lean sources. Run `bun run check:lean` and `bun run check:separators` from the repository root to reproduce these gates. Install Lean dependencies before committing; the hook does not download dependencies automatically.
