import { describe, expect, it } from "vitest";
import { bootRole, type BootDeps } from "./boot.js";

function recordingDeps(): { deps: BootDeps; started: string[]; exits: number[]; logs: string[] } {
  const started: string[] = [];
  const exits: number[] = [];
  const logs: string[] = [];
  const deps: BootDeps = {
    start: (role) => {
      started.push(role);
      return Promise.resolve();
    },
    exit: (code) => {
      exits.push(code);
    },
    log: (message) => {
      logs.push(message);
    },
  };
  return { deps, started, exits, logs };
}

describe("bootRole", () => {
  it("starts the role it was given", async () => {
    const { deps, started, exits } = recordingDeps();

    await bootRole({ ROLE: "worker" }, deps);

    expect(started).toEqual(["worker"]);
    expect(exits).toEqual([]);
  });

  it("exits with code 1 and a clear message for an unknown ROLE, without starting anything", async () => {
    const { deps, started, exits, logs } = recordingDeps();

    await bootRole({ ROLE: "bogus" }, deps);

    expect(started).toEqual([]);
    expect(exits).toEqual([1]);
    expect(logs[0]).toMatch(/ROLE must be one of api, worker, media-worker, realtime/);
  });

  it("exits with code 1 when ROLE is missing", async () => {
    const { deps, started, exits } = recordingDeps();

    await bootRole({}, deps);

    expect(started).toEqual([]);
    expect(exits).toEqual([1]);
  });
});
