import { readFileSync } from "node:fs";
import { z } from "zod";
import { checkContracts, type ContractInput } from "./check-contracts.js";
import { parseContractMeta } from "./contract-meta.js";

const documentSchema = z.object({ paths: z.record(z.string(), z.unknown()).optional() });

// Usage: check <base-openapi.json> <current-openapi.json> <base-contract.json> <current-contract.json>
const [basePath, currentPath, baseContractPath, currentContractPath] = process.argv.slice(2);
if (basePath === undefined || currentPath === undefined || baseContractPath === undefined || currentContractPath === undefined) {
  process.stderr.write("usage: check <base.json> <current.json> <base-contract.json> <current-contract.json>\n");
  process.exit(2);
}

function readInput(openApiPath: string, contractPath: string): ContractInput {
  return {
    document: documentSchema.parse(JSON.parse(readFileSync(openApiPath, "utf8"))),
    contract: parseContractMeta(readFileSync(contractPath, "utf8")),
  };
}

const result = checkContracts({
  base: readInput(basePath, baseContractPath),
  current: readInput(currentPath, currentContractPath),
});

for (const change of result.breaking) {
  process.stdout.write(`breaking: ${change}\n`);
}
if (!result.allowed) {
  process.stderr.write(`contract check failed: ${result.reason ?? "breaking change"}\n`);
  process.exit(1);
}
process.stdout.write(result.breaking.length === 0 ? "contract check passed: no breaking change\n" : "contract check passed: breaking change allowed by version bump and overlap\n");
