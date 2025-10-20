import { zkit } from "hardhat";
import { expect } from "chai";
import { TikTakToe } from "@zkit";

describe("TikTakToe", () => {
  let circuit: TikTakToe;

  before(async () => {
    circuit = await zkit.getCircuit("TikTakToe");
  });

  describe("row wins", () => {
    it("should detect top row win for player 1", async () => {
      await expect(circuit)
        .with.witnessInputs({
          board: [
            [1, 1, 1],
            [0, 2, 0],
            [2, 0, 2],
          ],
          player: 1,
        })
        .to.have.witnessOutputs({ has_won: 1 });
    });

    it("should detect middle row win for player 0", async () => {
      await expect(circuit)
        .with.witnessInputs({
          board: [
            [1, 2, 1],
            [0, 0, 0],
            [2, 1, 2],
          ],
          player: 0,
        })
        .to.have.witnessOutputs({ has_won: 1 });
    });
  });

  describe("column wins", () => {
    it("should detect left column win for player 1", async () => {
      await expect(circuit)
        .with.witnessInputs({
          board: [
            [1, 0, 2],
            [1, 2, 0],
            [1, 0, 2],
          ],
          player: 1,
        })
        .to.have.witnessOutputs({ has_won: 1 });
    });

    it("should detect right column win for player 0", async () => {
      await expect(circuit)
        .with.witnessInputs({
          board: [
            [1, 2, 0],
            [2, 1, 0],
            [1, 2, 0],
          ],
          player: 0,
        })
        .to.have.witnessOutputs({ has_won: 1 });
    });
  });

  describe("diagonal wins", () => {
    it("should detect main diagonal win for player 1", async () => {
      await expect(circuit)
        .with.witnessInputs({
          board: [
            [1, 0, 2],
            [0, 1, 2],
            [2, 0, 1],
          ],
          player: 1,
        })
        .to.have.witnessOutputs({ has_won: 1 });
    });

    it("should detect anti-diagonal win for player 0", async () => {
      await expect(circuit)
        .with.witnessInputs({
          board: [
            [1, 2, 0],
            [2, 0, 1],
            [0, 1, 2],
          ],
          player: 0,
        })
        .to.have.witnessOutputs({ has_won: 1 });
    });
  });

  describe("no win scenarios", () => {
    it("should return 0 for partial board with no winner", async () => {
      await expect(circuit)
        .with.witnessInputs({
          board: [
            [0, 1, 0],
            [0, 2, 1],
            [1, 0, 2],
          ],
          player: 1,
        })
        .to.have.witnessOutputs({ has_won: 0 });
    });

    it("should return 0 when checking wrong player", async () => {
      await expect(circuit)
        .with.witnessInputs({
          board: [
            [1, 1, 1],
            [0, 2, 0],
            [2, 0, 2],
          ],
          player: 0,
        })
        .to.have.witnessOutputs({ has_won: 0 });
    });

    it("should return 0 for empty board", async () => {
      await expect(circuit)
        .with.witnessInputs({
          board: [
            [2, 2, 2],
            [2, 2, 2],
            [2, 2, 2],
          ],
          player: 1,
        })
        .to.have.witnessOutputs({ has_won: 0 });
    });

    it("should return 0 for near-win scenario", async () => {
      await expect(circuit)
        .with.witnessInputs({
          board: [
            [1, 1, 0],
            [0, 2, 1],
            [2, 0, 0],
          ],
          player: 1,
        })
        .to.have.witnessOutputs({ has_won: 0 });
    });
  });

  describe("constraint validation", () => {
    it("should reject board values outside {0,1,2}", async () => {
      await expect(
        circuit.generateProof({
          board: [
            [3, 1, 0],
            [0, 1, 2],
            [2, 1, 0],
          ],
          player: 1,
        })
      ).to.be.rejected;
    });

    it("should reject negative board values", async () => {
      await expect(
        circuit.generateProof({
          board: [
            [-1, 1, 0],
            [0, 1, 2],
            [2, 1, 0],
          ],
          player: 1,
        })
      ).to.be.rejected;
    });

    it("should reject player values outside {0,1}", async () => {
      await expect(
        circuit.generateProof({
          board: [
            [1, 1, 1],
            [0, 2, 0],
            [2, 0, 2],
          ],
          player: 2,
        })
      ).to.be.rejected;
    });

    it("should verify valid proof for winning configuration", async () => {
      const proof = await circuit.generateProof({
        board: [
          [1, 1, 1],
          [0, 2, 0],
          [2, 0, 2],
        ],
        player: 1,
      });
      expect(await circuit.verifyProof(proof)).to.be.true;
    });

    it("should verify valid proof for non-winning configuration", async () => {
      const proof = await circuit.generateProof({
        board: [
          [0, 1, 0],
          [0, 2, 1],
          [1, 0, 2],
        ],
        player: 1,
      });
      expect(await circuit.verifyProof(proof)).to.be.true;
    });
  });
});
