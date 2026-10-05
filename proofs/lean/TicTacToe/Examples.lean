import TicTacToe.Soundness

namespace TicTacToe

variable {F : Type*} [Field F]

/-- All cells belong to player zero; all eight lines match. -/
def filledWitness : Witness F where
  board := fun _ _ => 0
  player := 0
  lowBit := fun _ _ => 0
  highBit := fun _ _ => 0
  equal := fun _ _ => 1
  equalInverse := fun _ _ => 0
  rowProduct := fun _ _ => 1
  colProduct := fun _ _ => 1
  mainProduct := fun _ => 1
  antiProduct := fun _ => 1
  accumulator := fun i => (i.val : F)
  zeroFlag := 0
  finalInverse := (8 : F)⁻¹
  hasWon := 1

/-- Every cell is empty; no line matches player zero. -/
def emptyWitness : Witness F where
  board := fun _ _ => 2
  player := 0
  lowBit := fun _ _ => 0
  highBit := fun _ _ => 1
  equal := fun _ _ => 0
  equalInverse := fun _ _ => (-2 : F)⁻¹
  rowProduct := fun _ k => if k = 0 then 1 else 0
  colProduct := fun _ k => if k = 0 then 1 else 0
  mainProduct := fun k => if k = 0 then 1 else 0
  antiProduct := fun k => if k = 0 then 1 else 0
  accumulator := fun _ => 0
  zeroFlag := 1
  finalInverse := 0
  hasWon := 0

theorem filled_constraints (q : ℕ) [CharP F q] (hq : 8 < q) :
    Constraints (filledWitness : Witness F) := by
  have h8 : (8 : F) ≠ 0 := by
    intro h
    have := (count_cast_zero_iff (F := F) q hq 8 (by omega)).mp h
    omega
  have hl (i : Fin 8) : lineValue (filledWitness : Witness F) i = 1 := by
    fin_cases i <;> norm_num [lineValue, filledWitness]
  constructor <;> intros <;>
    try simp only [hl]
  all_goals try simp [filledWitness, Fin.val_succ, Nat.cast_add, mul_inv_cancel₀ h8]
  change (0 : F) = 1 - (8 : F) * (8 : F)⁻¹
  simp [mul_inv_cancel₀ h8]

theorem empty_constraints (q : ℕ) [CharP F q] (hq : 8 < q) :
    Constraints (emptyWitness : Witness F) := by
  have h2 : (2 : F) ≠ 0 := by
    intro h
    have := (count_cast_zero_iff (F := F) q hq 2 (by omega)).mp h
    omega
  have hn : (-2 : F) ≠ 0 := neg_ne_zero.mpr h2
  have h3 : (3 : Fin 4) ≠ 0 := by decide
  have hl (i : Fin 8) : lineValue (emptyWitness : Witness F) i = 0 := by
    fin_cases i <;> norm_num [lineValue, emptyWitness, h3]
  constructor <;> intros <;>
    try simp only [hl]
  all_goals simp [emptyWitness, mul_inv_cancel₀ hn, mul_inv_cancel₀ h2, Fin.succ_ne_zero]

/-- The constraint relation admits a witness with output one. -/
theorem winning_satisfiable (q : ℕ) [CharP F q] (hq : 8 < q) :
    ∃ w : Witness F, Constraints w ∧ w.hasWon = 1 ∧ Wins w := by
  refine ⟨filledWitness, filled_constraints q hq, rfl, ?_⟩
  exact (winning_iff q hq filledWitness (filled_constraints q hq)).mp rfl

/-- The constraint relation also admits a witness with output zero. -/
theorem nonwinning_satisfiable (q : ℕ) [CharP F q] (hq : 8 < q) :
    ∃ w : Witness F, Constraints w ∧ w.hasWon = 0 ∧ ¬ Wins w := by
  refine ⟨emptyWitness, empty_constraints q hq, rfl, ?_⟩
  intro hw
  have ho := (winning_iff q hq emptyWitness (empty_constraints q hq)).mpr hw
  change (0 : F) = 1 at ho
  exact zero_ne_one ho

end TicTacToe
