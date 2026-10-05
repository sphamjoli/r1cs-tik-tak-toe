import TicTacToe.Constraints
import Mathlib.Tactic.FinCases
import Mathlib.Tactic.NormNum

namespace TicTacToe

open Classical

variable {F : Type*} [Field F]

/-- Both IsZero equations are needed, even when its inverse signal is arbitrary. -/
theorem isZero_sound (x inverse flag : F)
    (output : flag = 1 - x * inverse) (product : x * flag = 0) :
    flag = if x = 0 then 1 else 0 := by
  classical
  by_cases hx : x = 0
  · simpa [hx] using output
  · have hz : flag = 0 := (mul_eq_zero.mp product).resolve_left hx
    simp [hx, hz]

theorem bit_domain (x : F) (h : x * (x - 1) = 0) : x = 0 ∨ x = 1 := by
  rcases mul_eq_zero.mp h with h | h
  · exact Or.inl h
  · exact Or.inr (sub_eq_zero.mp h)

theorem player_domain (w : Witness F) (h : Constraints w) :
    w.player = 0 ∨ w.player = 1 := bit_domain w.player h.playerBit

theorem cell_domain (w : Witness F) (h : Constraints w) (i j : Fin 3) :
    w.board i j = 0 ∨ w.board i j = 1 ∨ w.board i j = 2 := by
  rcases bit_domain _ (h.lowBit i j) with hl | hl <;>
    rcases bit_domain _ (h.highBit i j) with hh | hh
  · simp [h.cellEncoding i j, hl, hh]
  · simp [h.cellEncoding i j, hl, hh]
  · simp [h.cellEncoding i j, hl, hh]
  · have impossible := h.exclusiveBits i j
    simp [hl, hh] at impossible

theorem equality_sound (w : Witness F) (h : Constraints w) (i j : Fin 3) :
    w.equal i j = if w.board i j = w.player then 1 else 0 := by
  classical
  have hz := isZero_sound (w.player - w.board i j) (w.equalInverse i j)
    (w.equal i j) (h.equalityOutput i j) (h.equalityZero i j)
  rw [sub_eq_zero] at hz
  simpa only [eq_comm] using hz

theorem row_product (w : Witness F) (h : Constraints w) (i : Fin 3) :
    w.rowProduct i 3 = w.equal i 0 * w.equal i 1 * w.equal i 2 := by
  calc
    w.rowProduct i 3 = w.rowProduct i 2 * w.equal i 2 := h.rowStep i 2
    _ = w.equal i 0 * w.equal i 1 * w.equal i 2 := by
      have h1 : w.rowProduct i 2 = w.rowProduct i 1 * w.equal i 1 := h.rowStep i 1
      have h0 : w.rowProduct i 1 = w.rowProduct i 0 * w.equal i 0 := h.rowStep i 0
      rw [h1, h0, h.rowInitial i]
      simp

theorem col_product (w : Witness F) (h : Constraints w) (j : Fin 3) :
    w.colProduct j 3 = w.equal 0 j * w.equal 1 j * w.equal 2 j := by
  calc
    w.colProduct j 3 = w.colProduct j 2 * w.equal 2 j := h.colStep j 2
    _ = w.equal 0 j * w.equal 1 j * w.equal 2 j := by
      have h1 : w.colProduct j 2 = w.colProduct j 1 * w.equal 1 j := h.colStep j 1
      have h0 : w.colProduct j 1 = w.colProduct j 0 * w.equal 0 j := h.colStep j 0
      rw [h1, h0, h.colInitial j]
      simp

theorem main_product (w : Witness F) (h : Constraints w) :
    w.mainProduct 3 = w.equal 0 0 * w.equal 1 1 * w.equal 2 2 := by
  calc
    w.mainProduct 3 = w.mainProduct 2 * w.equal 2 2 := h.mainStep 2
    _ = w.equal 0 0 * w.equal 1 1 * w.equal 2 2 := by
      have h1 : w.mainProduct 2 = w.mainProduct 1 * w.equal 1 1 := h.mainStep 1
      have h0 : w.mainProduct 1 = w.mainProduct 0 * w.equal 0 0 := h.mainStep 0
      rw [h1, h0, h.mainInitial]
      simp

theorem anti_product (w : Witness F) (h : Constraints w) :
    w.antiProduct 3 = w.equal 0 2 * w.equal 1 1 * w.equal 2 0 := by
  calc
    w.antiProduct 3 = w.antiProduct 2 * w.equal 2 (mirror 2) := h.antiStep 2
    _ = w.equal 0 2 * w.equal 1 1 * w.equal 2 0 := by
      have h1 : w.antiProduct 2 = w.antiProduct 1 * w.equal 1 (mirror 1) := h.antiStep 1
      have h0 : w.antiProduct 1 = w.antiProduct 0 * w.equal 0 (mirror 0) := h.antiStep 0
      rw [h1, h0, h.antiInitial]
      simp [mirror]

theorem indicator_product (P Q R : Prop) [Decidable P] [Decidable Q] [Decidable R] :
    (if P then (1 : F) else 0) * (if Q then 1 else 0) * (if R then 1 else 0) =
    if P ∧ Q ∧ R then 1 else 0 := by
  split_ifs <;> simp_all

theorem line_sound (w : Witness F) (h : Constraints w) (l : Fin 8) :
    lineValue w l = (winBit w l : F) := by
  classical
  fin_cases l <;>
    norm_num [lineValue, winBit, lineMatches, lineCells, mirror,
      row_product w h, col_product w h, main_product w h, anti_product w h,
      equality_sound w h, indicator_product] <;> split_ifs <;> simp_all

theorem accumulator_sound (w : Witness F) (h : Constraints w) :
    w.accumulator 8 = (winCount w : F) := by
  have h0 : w.accumulator 1 = w.accumulator 0 + lineValue w 0 := h.accumulatorStep 0
  have h1 : w.accumulator 2 = w.accumulator 1 + lineValue w 1 := h.accumulatorStep 1
  have h2 : w.accumulator 3 = w.accumulator 2 + lineValue w 2 := h.accumulatorStep 2
  have h3 : w.accumulator 4 = w.accumulator 3 + lineValue w 3 := h.accumulatorStep 3
  have h4 : w.accumulator 5 = w.accumulator 4 + lineValue w 4 := h.accumulatorStep 4
  have h5 : w.accumulator 6 = w.accumulator 5 + lineValue w 5 := h.accumulatorStep 5
  have h6 : w.accumulator 7 = w.accumulator 6 + lineValue w 6 := h.accumulatorStep 6
  have h7 : w.accumulator 8 = w.accumulator 7 + lineValue w 7 := h.accumulatorStep 7
  rw [h7, h6, h5, h4, h3, h2, h1, h0, h.accumulatorInitial]
  simp [line_sound w h, winCount, Nat.cast_add]

omit [Field F] in
theorem winBit_bound (w : Witness F) (l : Fin 8) : winBit w l ≤ 1 := by
  classical
  unfold winBit
  split_ifs <;> omega

omit [Field F] in
theorem winCount_bound (w : Witness F) : winCount w ≤ 8 := by
  have h0 := winBit_bound w 0
  have h1 := winBit_bound w 1
  have h2 := winBit_bound w 2
  have h3 := winBit_bound w 3
  have h4 := winBit_bound w 4
  have h5 := winBit_bound w 5
  have h6 := winBit_bound w 6
  have h7 := winBit_bound w 7
  unfold winCount
  omega

omit [Field F] in
theorem winBit_le_count (w : Witness F) (l : Fin 8) : winBit w l ≤ winCount w := by
  fin_cases l <;> simp only [Fin.mk_zero, Fin.reduceFinMk] <;> unfold winCount <;> omega

omit [Field F] in
theorem winCount_zero_iff (w : Witness F) : winCount w = 0 ↔ ¬ Wins w := by
  classical
  constructor
  · intro hz ⟨l, hl⟩
    have hb : winBit w l = 1 := by simp [winBit, hl]
    have bound := winBit_le_count w l
    omega
  · intro hn
    have hb (l : Fin 8) : winBit w l = 0 := by
      have hl : ¬ lineMatches w l := fun hl => hn ⟨l, hl⟩
      simp [winBit, hl]
    simp [winCount, hb]

/-- Counts zero through eight retain their value under reduction into this field. -/
theorem count_cast_zero_iff (q : ℕ) [CharP F q] (hq : 8 < q) (n : ℕ) (hn : n ≤ 8) :
    (n : F) = 0 ↔ n = 0 := by
  rw [CharP.cast_eq_zero_iff F q n]
  constructor
  · intro hd
    have hlt : n < q := lt_of_le_of_lt hn hq
    exact Nat.eq_zero_of_dvd_of_lt hd hlt
  · intro hn
    simp [hn]

/-- Every satisfying witness has exactly the geometrical win indicator. -/
theorem circuit_soundness (q : ℕ) [CharP F q] (hq : 8 < q)
    (w : Witness F) (h : Constraints w) :
    w.hasWon = if Wins w then 1 else 0 := by
  classical
  have hz := isZero_sound (w.accumulator 8) w.finalInverse w.zeroFlag h.zeroOutput h.zeroProduct
  have hc := count_cast_zero_iff (F := F) q hq (winCount w) (winCount_bound w)
  rw [h.output, hz, accumulator_sound w h]
  by_cases hw : Wins w
  · have hn : winCount w ≠ 0 := fun hn => (winCount_zero_iff w).mp hn hw
    have hf : (winCount w : F) ≠ 0 := fun hf => hn (hc.mp hf)
    simp [hf, hw]
  · have hn : winCount w = 0 := (winCount_zero_iff w).mpr hw
    simp [hn, hw]

theorem output_boolean (q : ℕ) [CharP F q] (hq : 8 < q)
    (w : Witness F) (h : Constraints w) : w.hasWon = 0 ∨ w.hasWon = 1 := by
  classical
  rw [circuit_soundness q hq w h]
  split_ifs <;> simp

theorem winning_iff (q : ℕ) [CharP F q] (hq : 8 < q)
    (w : Witness F) (h : Constraints w) : w.hasWon = 1 ↔ Wins w := by
  classical
  rw [circuit_soundness q hq w h]
  by_cases hw : Wins w <;> simp [hw]

/-- BN254's scalar modulus used by snarkjs and the Solidity verifier. -/
def bn254Modulus : ℕ :=
  21888242871839275222246405745257275088548364400416034343698204186575808495617

/-- Specialisation assumes field arithmetic of the recorded scalar characteristic. -/
theorem bn254_soundness [CharP F bn254Modulus] (w : Witness F) (h : Constraints w) :
    w.hasWon = if Wins w then 1 else 0 := by
  exact circuit_soundness bn254Modulus (by norm_num [bn254Modulus]) w h

end TicTacToe
