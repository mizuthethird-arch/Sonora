import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const configFile = fileURLToPath(new URL("../commitlint.config.js", import.meta.url));
const MAXIMUM_HEADER_LENGTH = 100;

function lintCommitMessage(message: string): { status: number | null; output: string } {
  const result = spawnSync("pnpm", ["exec", "commitlint", "--config", configFile], {
    input: message,
    encoding: "utf8",
  });
  expect(result.error).toBeUndefined();
  return { status: result.status, output: `${result.stdout}${result.stderr}` };
}

describe("the shared commitlint config", () => {
  it("rejects a message without a type", () => {
    const result = lintCommitMessage("fixed stuff");

    expect(result.status).not.toBe(0);
    expect(result.output).toContain("type-empty");
  });

  it("accepts a conventional message with a scope", () => {
    expect(lintCommitMessage("fix(api): return 404 for unknown track").status).toBe(0);
  });

  it("accepts a body and a trailer", () => {
    const message =
      "chore: update the lockfile\n\nThe tool needs a newer release.\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>";

    expect(lintCommitMessage(message).status).toBe(0);
  });

  it("rejects an unknown type", () => {
    const result = lintCommitMessage("stuff: change things");

    expect(result.status).not.toBe(0);
    expect(result.output).toContain("type-enum");
  });

  it("rejects a header that is too long", () => {
    const result = lintCommitMessage(`fix: ${"x".repeat(MAXIMUM_HEADER_LENGTH)}`);

    expect(result.status).not.toBe(0);
    expect(result.output).toContain("header-max-length");
  });

  it("rejects an empty message", () => {
    expect(lintCommitMessage("").status).not.toBe(0);
  });

  it("accepts a Dependabot title with a capital Bump", () => {
    expect(lintCommitMessage("chore(deps): Bump redis from 7-alpine to 8-alpine").status).toBe(0);
  });

  it("accepts a Dependabot dev dependency title with a capital Bump", () => {
    expect(
      lintCommitMessage("chore(deps-dev): Bump @types/node from 24.19.2 to 26.6.6").status,
    ).toBe(0);
  });

  it("still rejects other sentence-case subjects", () => {
    const result = lintCommitMessage("fix(api): Return 404 for unknown track");

    expect(result.status).not.toBe(0);
    expect(result.output).toContain("subject-case");
  });
});
