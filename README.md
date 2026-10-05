# Tic-tac-toe circuit and game

The circuit computes a winning-line indicator for a public board and player. Its public signals are `[has_won, nine row-major board cells, player]`. Non-winning boards also have valid proofs; the contract requires `has_won = 1` before paying a winning claim.

Both players must deposit exactly one stake before play. Player 0 starts, and each player must reveal their commitment before the next turn. Use `moveCommitment(gameId, move)` to obtain the canonical hash bound to the chain, proxy and game. Call `commitMove`, then `revealMove` from the same player. Reveals authenticate the player, reject occupied cells and stop play at the first win. A full board without a winner refunds both stakes.

Each commitment and reveal has a one-day deadline. After a missed deadline, only the other player can call `claimTimeout` to claim that game's two stakes. Unjoined games can be cancelled independently of other games. Winning boards are settled with `revealAndClaimWin`, the complete revealed transcript and a matching Groth16 proof.

Existing live games must be settled before adopting this implementation. Old funding and commitment authors cannot be recovered safely from the earlier storage. Local key generation is for development; deployment requires independently secured ceremony artifacts.

### Board Representation

The game uses a 3×3 board encoded as a matrix B over the BN254 scalar field. Each cell B[i,j] ∈ {0, 1, 2} represents player 0, player 1, or an empty cell respectively. The checked player p ∈ {0, 1}.

### Equality Constraint System

For player p and board position B[i,j], we define the equality indicator:

**E[i,j] = δ(B[i,j], p)**

where δ(a,b) = 1 if a = b, and 0 otherwise.

This is enforced through both polynomial constraints:
**(B[i,j] - p) · w[i,j] = E[i,j] - 1**
**(B[i,j] - p) · E[i,j] = 0**

with auxiliary variable w[i,j], ensuring E[i,j] ∈ {0,1} and E[i,j] = 1 ⟺ B[i,j] = p.

### Line Verification Formula

For any line L = {(i₁,j₁), (i₂,j₂), ..., (iₙ,jₙ)}, the winning condition is:

**W*L = ∏*{k=1}^n E[iₖ,jₖ]**

This product equals 1 if and only if all positions in line L contain player p's marker.

### Complete Win Detection

The total winning indicator aggregates all possible lines:

**W*total = ∑*{L ∈ Lines} W_L**

where Lines represents all rows, columns, and diagonals.

### Non-Zero Verification

To compute whether W_total is non-zero, the circuit uses the constraint system:

**W_total · z = 1 - s**
**W_total · s = 0**
**s · (1 - s) = 0**

where s ∈ {0,1}, s = 1 ⟺ W_total = 0, and has_won = 1 - s. A 3×3 board has eight possible winning lines, so the sum is at most eight and cannot wrap around the field modulus. The boolean constraint on s follows from the first two equations; the imported IsZero gadget enforces those two equations.

## Worked Example

Consider the 3×3 board:

```
B = [[1, 1, 1],
     [0, 0, 2],
     [2, 2, 0]]
```

For player p = 1:

**Step 1: Equality Matrix**

```
E = [[1, 1, 1],
     [0, 0, 0],
     [0, 0, 0]]
```

**Step 2: Line Products**

- Row 0: W_R₀ = E[0,0] × E[0,1] × E[0,2] = 1 × 1 × 1 = 1
- Row 1: W_R₁ = E[1,0] × E[1,1] × E[1,2] = 0 × 0 × 0 = 0
- Row 2: W_R₂ = E[2,0] × E[2,1] × E[2,2] = 0 × 0 × 0 = 0
- Col 0: W_C₀ = E[0,0] × E[1,0] × E[2,0] = 1 × 0 × 0 = 0
- Col 1: W_C₁ = E[0,1] × E[1,1] × E[2,1] = 1 × 0 × 0 = 0
- Col 2: W_C₂ = E[0,2] × E[1,2] × E[2,2] = 1 × 0 × 0 = 0
- Diag 1: W_D₁ = E[0,0] × E[1,1] × E[2,2] = 1 × 0 × 0 = 0
- Diag 2: W_D₂ = E[0,2] × E[1,1] × E[2,0] = 1 × 0 × 0 = 0

**Step 3: Aggregation**
W_total = 1 + 0 + 0 + 0 + 0 + 0 + 0 + 0 = 1

**Step 4: Non-Zero Verification**
Since W_total = 1 ≠ 0, the constraint W_total · z = 1 - s has solution z = 1, s = 0.

Therefore, has_won = 1 confirms a winning line for player 1. The contract separately authenticates the moves and checks that play stopped at the first win.

## Constraint Polynomial

The detector includes domain constraints as well as the winning-line equations. For each cell, the two bits b₀ and b₁ satisfy:

**b₀ · (b₀ - 1) = 0**
**b₁ · (b₁ - 1) = 0**
**B[i,j] = b₀ + 2b₁**
**b₀ · b₁ = 0**

These restrict the cell to 0, 1 or 2. The player satisfies **p · (p - 1) = 0**. Within those domains, the winning-line equations are:

**∀i,j: (B[i,j] - p) · w[i,j] = E[i,j] - 1**
**∀i,j: (B[i,j] - p) · E[i,j] = 0**
**∀L ∈ Lines: W*L = ∏*{(i,j) ∈ L} E[i,j]**
**W*total = ∑*{L ∈ Lines} W_L**
**W_total · z = 1 - s**
**W_total · s = 0**
**s · (1 - s) = 0**

The detector returns has_won = 1 if and only if the specified player occupies a complete winning line. It does not prove turn order, move ownership, funding or game identity. Those checks belong to the contract's recorded game state.

## Installation

Bun 1.3.5 manages dependencies and repository commands. Node.js is also required by Hardhat, snarkjs and the ceremony contribution helper; snarkjs contribution workers are incompatible with Bun 1.3.5. `bun install --frozen-lockfile` installs the pinned local tooling. `make all` compiles the circuit, generates development keys with fresh entropy, verifies the key against the R1CS, and generates the verifier and proof fixtures. Do not deploy local ceremony keys as production artifacts.

## Testing (Hardhat)

`bun run test` tests the circuit through Hardhat ZKit. It may download its configured compiler and Powers of Tau artifacts. This command is separate from the Foundry game integration tests below.

## Testing (Foundry)

Run `make all`, then `forge test --offline --fuzz-runs 1000 -vv`. Tests use the actual verifier, cover winning and non-winning proofs, legal moves, escrow isolation, draws, timeouts and upgrade authority. The stateful invariant handler exercises multiple games, real proof payouts and withdrawals while checking escrow liabilities and Ether backing.

For exhaustive detector checks, run `bun run test:soundness`.

The checker evaluates all 39,366 board/player combinations against the R1CS, rejects flipped-output witnesses and checks invalid input boundaries. These checks and constraint reasoning do not constitute a machine-checked formal proof.

## Formal circuit proof

The [Lean proof](proofs/lean/README.md) states the detector theorem in plain language and mathematical notation, with its assumptions and evidence boundary. Run `bun proofs/lean/check.cjs --setup` once, then `bun run test:formal` to check the reviewed sources, build the proofs and audit their axioms.

## Commit checks

`bun install --frozen-lockfile` installs Lefthook through the `prepare` script. Use `bun run prepare` to reinstall the hooks in an existing checkout. The [hook configuration](lefthook.yml) follows the masters project's separate-job structure. Every commit runs the repository-wide decorative-comment check and the Lean source, build and axiom checks. Solidity and shell changes also trigger formatting and syntax checks. Hooks report failures without rewriting or staging files.

Run `bun run check` to check comments, Lean proofs and Solidity formatting manually. The Lean dependencies must first be installed with `bun proofs/lean/check.cjs --setup`; missing tools or dependencies fail the commit check.
