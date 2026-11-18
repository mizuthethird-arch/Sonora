import { type OpenApiDocument } from "../openapi/openapi.js";
import { type ContractSnapshot, decideCompatibility, findBreakingChanges } from "../compat/compatibility.js";

export type ContractMeta = {
  readonly version: string;
  // The date until which the previous version keeps working, or null when none is noted.
  readonly overlapUntil: string | null;
};

export type ContractInput = {
  readonly document: OpenApiDocument;
  readonly contract: ContractMeta;
};

export type CheckResult = {
  readonly allowed: boolean;
  readonly breaking: readonly string[];
  readonly reason?: string;
};

// Compares the current contract with its base. A breaking change needs a version bump and a noted overlap period.
export function checkContracts(input: { base: ContractInput; current: ContractInput }): CheckResult {
  const breaking = findBreakingChanges(toSnapshot(input.base), toSnapshot(input.current));
  const decision = decideCompatibility({
    breaking,
    baseVersion: input.base.contract.version,
    currentVersion: input.current.contract.version,
    overlapUntil: input.current.contract.overlapUntil,
  });
  return decision.allowed ? { allowed: true, breaking } : { allowed: false, breaking, reason: decision.reason };
}

function toSnapshot(input: ContractInput): ContractSnapshot {
  return { version: input.contract.version, paths: input.document.paths ?? {} };
}
