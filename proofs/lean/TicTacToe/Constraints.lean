import Mathlib.Algebra.CharP.Basic
import Mathlib.Algebra.Field.Basic
import Mathlib.Data.Fin.VecNotation

/-! A source-level model of the signal equations in TikTakToe(3).
The witness fields include arbitrary auxiliary signals, not just generated witnesses. -/
namespace TicTacToe

open Classical

abbrev Board (F : Type*) := Fin 3 → Fin 3 → F

def mirror (i : Fin 3) : Fin 3 := ⟨2 - i.val, by omega⟩

/-- Row-major rows, columns, main diagonal and anti-diagonal. -/
def lineCells : Fin 8 → Fin 3 → Fin 3 × Fin 3 :=
  ![fun j => (0, j), fun j => (1, j), fun j => (2, j),
    fun i => (i, 0), fun i => (i, 1), fun i => (i, 2),
    fun i => (i, i), fun i => (i, mirror i)]

structure Witness (F : Type*) where
  board : Board F
  player : F
  lowBit : Board F
  highBit : Board F
  equal : Board F
  equalInverse : Board F
  rowProduct : Fin 3 → Fin 4 → F
  colProduct : Fin 3 → Fin 4 → F
  mainProduct : Fin 4 → F
  antiProduct : Fin 4 → F
  accumulator : Fin 9 → F
  zeroFlag : F
  finalInverse : F
  hasWon : F

def lineValue {F : Type*} (w : Witness F) : Fin 8 → F :=
  ![w.rowProduct 0 3, w.rowProduct 1 3, w.rowProduct 2 3,
    w.colProduct 0 3, w.colProduct 1 3, w.colProduct 2 3,
    w.mainProduct 3, w.antiProduct 3]

/-- Polynomial constraints; no witness-generation algorithm is assumed. -/
structure Constraints {F : Type*} [Field F] (w : Witness F) : Prop where
  playerBit : w.player * (w.player - 1) = 0
  lowBit : ∀ i j, w.lowBit i j * (w.lowBit i j - 1) = 0
  highBit : ∀ i j, w.highBit i j * (w.highBit i j - 1) = 0
  cellEncoding : ∀ i j, w.board i j = w.lowBit i j + 2 * w.highBit i j
  exclusiveBits : ∀ i j, w.lowBit i j * w.highBit i j = 0
  equalityOutput : ∀ i j,
    w.equal i j = 1 - (w.player - w.board i j) * w.equalInverse i j
  equalityZero : ∀ i j, (w.player - w.board i j) * w.equal i j = 0
  rowInitial : ∀ i, w.rowProduct i 0 = 1
  rowStep : ∀ i (j : Fin 3),
    w.rowProduct i j.succ = w.rowProduct i j.castSucc * w.equal i j
  colInitial : ∀ j, w.colProduct j 0 = 1
  colStep : ∀ j (i : Fin 3),
    w.colProduct j i.succ = w.colProduct j i.castSucc * w.equal i j
  mainInitial : w.mainProduct 0 = 1
  mainStep : ∀ i : Fin 3,
    w.mainProduct i.succ = w.mainProduct i.castSucc * w.equal i i
  antiInitial : w.antiProduct 0 = 1
  antiStep : ∀ i : Fin 3,
    w.antiProduct i.succ = w.antiProduct i.castSucc * w.equal i (mirror i)
  accumulatorInitial : w.accumulator 0 = 0
  accumulatorStep : ∀ i : Fin 8,
    w.accumulator i.succ = w.accumulator i.castSucc + lineValue w i
  zeroOutput : w.zeroFlag = 1 - w.accumulator 8 * w.finalInverse
  zeroProduct : w.accumulator 8 * w.zeroFlag = 0
  output : w.hasWon = 1 - w.zeroFlag

/-- The specified player occupies all three cells of a geometrical line. -/
def lineMatches {F : Type*} (w : Witness F) (l : Fin 8) : Prop :=
  w.board (lineCells l 0).1 (lineCells l 0).2 = w.player ∧
  w.board (lineCells l 1).1 (lineCells l 1).2 = w.player ∧
  w.board (lineCells l 2).1 (lineCells l 2).2 = w.player

def Wins {F : Type*} (w : Witness F) : Prop := ∃ l : Fin 8, lineMatches w l

noncomputable def winBit {F : Type*} (w : Witness F) (l : Fin 8) : ℕ :=
  if lineMatches w l then 1 else 0

noncomputable def winCount {F : Type*} (w : Witness F) : ℕ :=
  winBit w 0 + winBit w 1 + winBit w 2 + winBit w 3 +
  winBit w 4 + winBit w 5 + winBit w 6 + winBit w 7

end TicTacToe
