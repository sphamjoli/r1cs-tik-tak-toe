import "@solarity/hardhat-zkit";
import "@solarity/chai-zkit";
import "tsconfig-paths/register";

module.exports = {
  zkit: {
    compilerVersion: "2.1.9",
    circuitsDir: "circuits",
    compilationSettings: {
      artifactsDir: "zkit/artifacts",
      onlyFiles: [],
      skipFiles: [],
      c: false,
      json: false,
    },
    setupSettings: {
      contributionSettings: {
        contributionTemplate: "groth16",
        contributions: 1,
      },
      onlyFiles: [],
      skipFiles: [],
      ptauDir: undefined,
      ptauDownload: true,
    },
    typesSettings: {
      typesArtifactsDir: "zkit/abi",
      typesDir: "generated-types/zkit",
    },
    verifiersDir: "contracts/verifiers",
    verifiersType: "sol",
    nativeCompiler: false,
    quiet: false,
  },
};
