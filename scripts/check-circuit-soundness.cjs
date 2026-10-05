// Exhaustive detector checks and witness mutations; not a formal proof of the protocol.
// Compile and export the R1CS into a directory, then pass that directory as argv[2].
const fs = require("fs");
const path = require("path");
const artifactDir = path.resolve(process.argv[2] || ".");
const build = require(
  path.join(artifactDir, "tic_tak_toe_js/witness_calculator.js"),
);
const r = JSON.parse(fs.readFileSync(path.join(artifactDir, "r1cs.json")));
const prime = BigInt(r.prime);
const mod = (x) => ((x % prime) + prime) % prime;
const constraints = r.constraints.map((c) =>
  c.map((l) => Object.entries(l).map(([i, v]) => [Number(i), BigInt(v)])),
);
const valid = (w) =>
  constraints.every(([a, b, c]) => {
    const evalLC = (l) => mod(l.reduce((s, [i, v]) => s + w[i] * v, 0n));
    return mod(evalLC(a) * evalLC(b) - evalLC(c)) === 0n;
  });
const lines = [
  [0, 1, 2],
  [3, 4, 5],
  [6, 7, 8],
  [0, 3, 6],
  [1, 4, 7],
  [2, 5, 8],
  [0, 4, 8],
  [2, 4, 6],
];
(async () => {
  const calc = await build(
    fs.readFileSync(path.join(artifactDir, "tic_tak_toe_js/tic_tak_toe.wasm")),
  );
  let checked = 0,
    mutations = 0;
  for (let code = 0; code < 3 ** 9; code++) {
    let n = code;
    const flat = Array.from({ length: 9 }, () => {
      const x = n % 3;
      n = Math.floor(n / 3);
      return x;
    });
    const board = [flat.slice(0, 3), flat.slice(3, 6), flat.slice(6, 9)];
    for (let player = 0; player < 2; player++) {
      const w = await calc.calculateWitness({ board, player }, true);
      const expected = lines.some((l) => l.every((i) => flat[i] === player))
        ? 1n
        : 0n;
      if (w[1] !== expected || !valid(w))
        throw Error("wrong output or unsatisfied R1CS " + code + " " + player);
      w[1] = 1n - w[1];
      if (valid(w)) throw Error("flipped output satisfies R1CS");
      checked++;
      mutations++;
    }
  }
  let rejected = 0;
  for (const value of [-1, 3, 4, prime - 1n]) {
    for (let cell = 0; cell < 9; cell++) {
      const flat = Array(9).fill(2);
      flat[cell] = value;
      try {
        await calc.calculateWitness(
          {
            board: [flat.slice(0, 3), flat.slice(3, 6), flat.slice(6, 9)],
            player: 0,
          },
          true,
        );
        throw Error("accepted invalid cell");
      } catch (e) {
        if (e.message === "accepted invalid cell") throw e;
        rejected++;
      }
    }
  }
  for (const player of [-1, 2, 3, prime - 1n]) {
    try {
      await calc.calculateWitness(
        {
          board: [
            [2, 2, 2],
            [2, 2, 2],
            [2, 2, 2],
          ],
          player,
        },
        true,
      );
      throw Error("accepted invalid player");
    } catch (e) {
      if (e.message === "accepted invalid player") throw e;
      rejected++;
    }
  }
  console.log(
    JSON.stringify(
      {
        checked,
        mutationsRejected: mutations,
        invalidInputsRejected: rejected,
        constraints: constraints.length,
        publicSignalOrder: ["has_won", "board[0..8]", "player"],
      },
      null,
      2,
    ),
  );
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
