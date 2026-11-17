import { defineConfig } from "vitest/config";

// JUnit XML is written only when CI is set: reports/junit/config.xml at the repository root.
const ci = Boolean(process.env["CI"]);

export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
    // The ESLint and commitlint tests spawn tools and time out at 5s when the whole suite runs in parallel.
    testTimeout: 30000,
    reporters: ci ? ["default", "junit"] : ["default"],
    outputFile: { junit: "../../reports/junit/config.xml" },
  },
});
