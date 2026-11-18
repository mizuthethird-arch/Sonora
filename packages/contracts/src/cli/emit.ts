import { writeFileSync } from "node:fs";
import { buildMergedDocument } from "../openapi/openapi.js";
import { allRouteGroups } from "../routes/index.js";
import { readContractMeta } from "./contract-meta.js";

// Writes the merged OpenAPI document. Run from packages/contracts: node dist/cli/emit.js <out.json>
const outPath = process.argv[2];
if (outPath === undefined) {
  process.stderr.write("usage: emit <out.json>\n");
  process.exit(2);
}

const meta = readContractMeta("contract.json");
writeFileSync(outPath, `${JSON.stringify(buildMergedDocument(allRouteGroups, meta.version), null, 2)}\n`);
