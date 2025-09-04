# POC Tick tac toe circuit

This circuit proves that a given board configuration represents a valid winning state for a specified player.

### Board Representation

A board state is encoded as a matrix B ∈ F^(n×n) where F is a finite field and each entry B[i,j] ∈ {0, 1, 2} represents player 0, player 1, or empty cell respectively.

### Equality Constraint System

For player p and board position B[i,j], we define the equality indicator:

**E[i,j] = δ(B[i,j], p)**

where δ(a,b) = 1 if a = b, and 0 otherwise.

This is enforced through the polynomial constraint:
**(B[i,j] - p) · w[i,j] = E[i,j] - 1**

with auxiliary variable w[i,j], ensuring E[i,j] ∈ {0,1} and E[i,j] = 1 ⟺ B[i,j] = p.

### Line Verification Formula

For any line L = {(i₁,j₁), (i₂,j₂), ..., (iₙ,jₙ)}, the winning condition is:

**W_L = ∏_{k=1}^n E[iₖ,jₖ]**

This product equals 1 if and only if all positions in line L contain player p's marker.

### Complete Win Detection

The total winning indicator aggregates all possible lines:

**W_total = ∑_{L ∈ Lines} W_L**

where Lines represents all rows, columns, and diagonals.

### Non-Zero Verification

To verify W_total ≠ 0, we employ the constraint system:

**W_total · z = 1 - s**
**s · (1 - s) = 0**

where s ∈ {0,1} and s = 1 ⟺ W_total = 0.

## Worked Example

Consider the 3×3 board:
```
B = [[1, 1, 1],
     [0, 0, 2],
     [2, 1, 0]]
```

For player p = 1:

**Step 1: Equality Matrix**
```
E = [[1, 1, 1],
     [0, 0, 0],
     [0, 1, 0]]
```

**Step 2: Line Products**
- Row 0: W_R₀ = E[0,0] × E[0,1] × E[0,2] = 1 × 1 × 1 = 1
- Row 1: W_R₁ = E[1,0] × E[1,1] × E[1,2] = 0 × 0 × 0 = 0
- Row 2: W_R₂ = E[2,0] × E[2,1] × E[2,2] = 0 × 1 × 0 = 0
- Col 0: W_C₀ = E[0,0] × E[1,0] × E[2,0] = 1 × 0 × 0 = 0
- Col 1: W_C₁ = E[0,1] × E[1,1] × E[2,1] = 1 × 0 × 1 = 0
- Col 2: W_C₂ = E[0,2] × E[1,2] × E[2,2] = 1 × 0 × 0 = 0
- Diag 1: W_D₁ = E[0,0] × E[1,1] × E[2,2] = 1 × 0 × 0 = 0
- Diag 2: W_D₂ = E[0,2] × E[1,1] × E[2,0] = 1 × 0 × 0 = 0

**Step 3: Aggregation**
W_total = 1 + 0 + 0 + 0 + 0 + 0 + 0 + 0 = 1

**Step 4: Non-Zero Verification**
Since W_total = 1 ≠ 0, the constraint W_total · z = 1 - s has solution z = 1, s = 0.

Therefore, s = 0 confirms the board represents a valid win for player 1.

## Constraint Polynomial

The complete verification reduces to satisfying the polynomial system:

**∀i,j: (B[i,j] - p) · w[i,j] = E[i,j] - 1**
**∀L ∈ Lines: W_L = ∏_{(i,j) ∈ L} E[i,j]**
**W_total = ∑_{L ∈ Lines} W_L**
**W_total · z = 1 - s**
**s · (1 - s) = 0**

The board is valid if and only if this system has a satisfying assignment with s = 0.


## Installation

``npm i``

## Testing

``npm run test``
