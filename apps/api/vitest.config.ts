import { configDefaults, defineConfig } from "vitest/config";

// JUnit XML is written only when CI is set: one file per run, reports/junit/api.xml at the repository root.
const ci = Boolean(process.env["CI"]);

export default defineConfig({
  test: {
    reporters: ci ? ["default", "junit"] : ["default"],
    outputFile: { junit: "../../reports/junit/api.xml" },
    projects: [
      {
        test: {
          name: "unit",
          include: ["src/**/*.test.ts"],
          exclude: [...configDefaults.exclude, "src/database/**"],
        },
      },
      {
        test: {
          name: "integration",
          include: ["src/database/**/*.test.ts"],
          fileParallelism: false,
          globalSetup: ["src/database/test/global-setup.ts"],
        },
      },
    ],
  },
});
