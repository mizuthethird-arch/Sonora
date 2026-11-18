import { fileURLToPath } from "node:url";
import { configDefaults, defineConfig } from "vitest/config";

// JUnit XML is written only when CI is set: one file per run, reports/junit/api.xml at the repository root.
const ci = Boolean(process.env["CI"]);

export default defineConfig({
  // Tests read the packages in this repository from source, not from their built output.
  resolve: {
    alias: {
      "@sonora/kernel": fileURLToPath(new URL("../../packages/kernel/src/index.ts", import.meta.url)),
      "@sonora/contracts": fileURLToPath(new URL("../../packages/contracts/src/index.ts", import.meta.url)),
    },
  },
  test: {
    reporters: ci ? ["default", "junit"] : ["default"],
    outputFile: { junit: "../../reports/junit/api.xml" },
    projects: [
      {
        test: {
          name: "unit",
          include: ["src/**/*.test.ts"],
          exclude: [...configDefaults.exclude, "src/database/**", "src/redis/**"],
        },
      },
      {
        test: {
          name: "integration",
          include: ["src/database/**/*.test.ts", "src/redis/**/*.test.ts"],
          fileParallelism: false,
          globalSetup: ["src/database/test/global-setup.ts"],
        },
      },
    ],
  },
});
