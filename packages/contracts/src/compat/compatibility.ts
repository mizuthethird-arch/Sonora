// The part of an OpenAPI document that the compatibility rules read.
export type ContractSnapshot = {
  readonly version: string;
  readonly paths: Readonly<Record<string, unknown>>;
};

export type CompatibilityInput = {
  readonly breaking: readonly string[];
  readonly baseVersion: string;
  readonly currentVersion: string;
  readonly overlapUntil: string | null;
};

export type CompatibilityDecision = { allowed: true } | { allowed: false; reason: string };

type Json = Readonly<Record<string, unknown>>;

// Lists what the current contract removes or narrows compared with the base. Added fields and widened enums are fine.
export function findBreakingChanges(base: ContractSnapshot, current: ContractSnapshot): string[] {
  const changes: string[] = [];
  for (const [path, operations] of Object.entries(base.paths)) {
    const currentOperations = current.paths[path];
    if (currentOperations === undefined) {
      changes.push(`removed path ${path}`);
      continue;
    }
    compareOperations(path, operations, currentOperations, changes);
  }
  return changes;
}

// Refuses a breaking change unless the version is bumped and an overlap period is noted.
export function decideCompatibility(input: CompatibilityInput): CompatibilityDecision {
  if (input.breaking.length === 0) {
    return { allowed: true };
  }
  if (input.currentVersion === input.baseVersion) {
    return { allowed: false, reason: "breaking change without a version bump" };
  }
  if (input.overlapUntil === null) {
    return { allowed: false, reason: "breaking change without a noted overlap period" };
  }
  return { allowed: true };
}

function compareOperations(path: string, base: unknown, current: unknown, changes: string[]): void {
  if (!isJson(base) || !isJson(current)) {
    return;
  }
  for (const [method, operation] of Object.entries(base)) {
    const currentOperation = current[method];
    if (currentOperation === undefined) {
      changes.push(`removed operation ${method.toUpperCase()} ${path}`);
      continue;
    }
    compareResponses(`${method.toUpperCase()} ${path}`, operation, currentOperation, changes);
  }
}

function compareResponses(location: string, base: unknown, current: unknown, changes: string[]): void {
  if (!isJson(base) || !isJson(current) || !isJson(base.responses) || !isJson(current.responses)) {
    return;
  }
  for (const [status, response] of Object.entries(base.responses)) {
    const currentResponse = current.responses[status];
    if (currentResponse === undefined) {
      changes.push(`removed response ${status} from ${location}`);
      continue;
    }
    compareContent(`${location} ${status}`, response, currentResponse, changes);
  }
}

function compareContent(location: string, base: unknown, current: unknown, changes: string[]): void {
  if (!isJson(base) || !isJson(current) || !isJson(base.content) || !isJson(current.content)) {
    return;
  }
  for (const [media, entry] of Object.entries(base.content)) {
    const currentEntry = current.content[media];
    if (!isJson(entry) || !isJson(currentEntry)) {
      continue;
    }
    compareSchema(location, entry.schema, currentEntry.schema, changes);
  }
}

function compareSchema(location: string, base: unknown, current: unknown, changes: string[]): void {
  if (!isJson(base) || !isJson(current)) {
    return;
  }
  if (Array.isArray(base.enum) && Array.isArray(current.enum)) {
    for (const value of base.enum) {
      if (!current.enum.includes(value)) {
        changes.push(`narrowed enum at ${location}: ${JSON.stringify(value)} removed`);
      }
    }
  }
  if ("const" in base && (("const" in current) || Array.isArray(current.enum))) {
    const allowed = "const" in current ? [current.const] : (current.enum as unknown[]);
    if (!allowed.includes(base.const)) {
      changes.push(`narrowed value at ${location}: ${JSON.stringify(base.const)} removed`);
    }
  }
  if (isJson(base.properties) && isJson(current.properties)) {
    for (const [key, property] of Object.entries(base.properties)) {
      if (!(key in current.properties)) {
        changes.push(`removed field ${location}.${key}`);
        continue;
      }
      compareSchema(`${location}.${key}`, property, current.properties[key], changes);
    }
  }
  if ("items" in base && "items" in current) {
    compareSchema(`${location}[]`, base.items, current.items, changes);
  }
}

function isJson(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
