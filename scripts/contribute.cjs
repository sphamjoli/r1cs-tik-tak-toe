// Supply fresh entropy directly to snarkjs, never through process arguments or logs.
const { randomBytes } = require("node:crypto");
const { powersOfTau, zKey } = require("snarkjs");

async function main() {
  const [kind, input, output, name] = process.argv.slice(2);
  if (!input || !output || !name || !["ptau", "zkey"].includes(kind)) {
    throw new Error(
      "Usage: node scripts/contribute.cjs ptau|zkey input output name",
    );
  }
  const ceremony = kind === "ptau" ? powersOfTau : zKey;
  await ceremony.contribute(
    input,
    output,
    name,
    randomBytes(64).toString("hex"),
  );
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
