import { readFileSync } from "node:fs";
import { z } from "zod";
import { type ContractMeta } from "./check-contracts.js";

const contractMetaSchema = z
  .object({
    version: z.string().regex(/^\d+\.\d+\.\d+$/),
    overlapUntil: z.iso.date().nullable(),
  })
  .strict();

export function parseContractMeta(text: string): ContractMeta {
  return contractMetaSchema.parse(JSON.parse(text));
}

export function readContractMeta(path: string): ContractMeta {
  return parseContractMeta(readFileSync(path, "utf8"));
}
