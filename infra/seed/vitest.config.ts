import { defineConfig } from "vitest/config";

// JUnit XML is written only when CI is set: reports/junit/seed.xml at the repository root.
const ci = Boolean(process.env["CI"]);

export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
    reporters: ci ? ["default", "junit"] : ["default"],
    outputFile: { junit: "../../reports/junit/seed.xml" },
  },
});
