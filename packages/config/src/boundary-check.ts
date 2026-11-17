import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { expect } from "vitest";

const boundaryConfig = fileURLToPath(new URL("../boundaries.cjs", import.meta.url));

export function runBoundaryCheckIn(directory: string): { status: number | null; output: string } {
  const result = spawnSync(
    "pnpm",
    ["exec", "depcruise", ".", "--config", boundaryConfig, "--output-type", "err-long"],
    { cwd: directory, encoding: "utf8" },
  );
  expect(result.error).toBeUndefined();
  return { status: result.status, output: `${result.stdout}${result.stderr}` };
}
