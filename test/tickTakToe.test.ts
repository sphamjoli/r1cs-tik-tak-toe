import { zkit } from "hardhat";
import { expect } from "chai";
import { TikTakToe } from "@zkit";

describe("TikTakToe", () => {
  it("should test the circuit", async () => {
    const circuit: TikTakToe = await zkit.getCircuit("TikTakToe");
    await expect(circuit)
      .with.witnessInputs({
        board: [
          [0, 1, 0],
          [0, 0, 1],
          [1, 0, 0],
        ],
        player: 1,
      })
      .to.have.witnessOutputs({ c: BigInt(1) });
    const proof = await circuit.generateProof({
      board: [
        [0, 1, 0],
        [0, 0, 1],
        [1, 0, 0],
      ],
      player: 1,
    });
    expect(await circuit.verifyProof(proof)).to.be.true;
  });
});
