// Check the reviewed source boundary, build the proof and reject unapproved proof axioms.
const { createHash } = require("node:crypto");
const { readFileSync, readdirSync } = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const project = __dirname;
const root = path.resolve(project, "../..");
const manifest = JSON.parse(
  readFileSync(path.join(project, "source-manifest.json"), "utf8")
);
const approvedAxioms = new Set(["propext", "Classical.choice", "Quot.sound"]);

function run(args) {
  const result = spawnSync("lake", args, {
    cwd: project,
    env: { ...process.env, MATHLIB_NO_CACHE_ON_UPDATE: "1" },
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  process.stdout.write(result.stdout);
  process.stderr.write(result.stderr);
  if (result.status !== 0) throw new Error(`lake ${args.join(" ")} failed`);
  return result.stdout;
}

function checkSources() {
  for (const [file, expected] of Object.entries(manifest.sourceFiles)) {
    const actual = createHash("sha256")
      .update(readFileSync(path.join(root, file)))
      .digest("hex");
    if (actual !== expected)
      throw new Error(
        `Reviewed source changed: ${file}. Review the Lean model before updating the manifest.`
      );
  }
  const version = JSON.parse(
    readFileSync(path.join(root, "node_modules/circomlib/package.json"), "utf8")
  ).version;
  if (version !== manifest.circomlibVersion)
    throw new Error("The reviewed circomlib version changed");
  function checkProofFiles(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      if (entry.name === ".lake") continue;
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) checkProofFiles(file);
      else if (entry.name.endsWith(".lean")) {
        const source = readFileSync(file, "utf8");
        if (/\b(sorry|admit|axiom|unsafe|native_decide)\b/.test(source))
          throw new Error(
            `Unapproved proof construct in ${path.relative(project, file)}`
          );
      }
    }
  }
  checkProofFiles(project);
  console.log("Reviewed Circom sources match the formal model boundary.");
}

try {
  checkSources();
  if (process.argv.includes("--sources-only")) process.exit(0);
  if (process.argv.includes("--setup")) {
    run(["update"]);
    run([
      "env",
      "lean",
      "--run",
      ".lake/packages/mathlib/Cache/Main.lean",
      "get",
      "Mathlib.Algebra.CharP.Basic",
      "Mathlib.Algebra.Field.Basic",
      "Mathlib.Data.Fin.VecNotation",
      "Mathlib.Tactic.FinCases",
      "Mathlib.Tactic.NormNum",
    ]);
  }
  run(["build"]);
  const audit = run([
    "env",
    "lean",
    "-DwarningAsError=true",
    "AxiomAudit.lean",
  ]);
  const entries = [
    ...audit.matchAll(/'([^']+)' depends on axioms: \[([^\]]*)\]/g),
  ];
  const expected = [
    "player_domain",
    "cell_domain",
    "circuit_soundness",
    "winning_iff",
    "bn254_soundness",
    "winning_satisfiable",
    "nonwinning_satisfiable",
  ];
  for (const theorem of expected) {
    const entry = entries.find((match) => match[1] === `TicTacToe.${theorem}`);
    if (!entry) throw new Error(`Missing axiom audit for ${theorem}`);
    for (const name of entry[2]
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean)) {
      if (!approvedAxioms.has(name))
        throw new Error(`Unapproved axiom in ${theorem}: ${name}`);
    }
  }
  console.log(
    "Circuit soundness theorem built; audited axioms are limited to standard Lean foundations."
  );
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
