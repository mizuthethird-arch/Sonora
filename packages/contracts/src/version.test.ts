import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { CONTRACT_VERSION } from "./version.js";

describe("CONTRACT_VERSION", () => {
  it("equals the version in contract.json", () => {
    const contract = JSON.parse(readFileSync(new URL("../contract.json", import.meta.url), "utf8")) as { version: string };

    expect(CONTRACT_VERSION).toBe(contract.version);
  });
});
