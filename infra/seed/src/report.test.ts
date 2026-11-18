import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { writeReport } from "./report.ts";
import type { SeedReport } from "./seed.ts";

describe("writeReport", () => {
  let directory = "";

  beforeEach(async () => {
    directory = await mkdtemp(join(tmpdir(), "seed-report-"));
  });

  afterEach(async () => {
    await rm(directory, { recursive: true, force: true });
  });

  it("writes the report to a file as JSON with the four fields", async () => {
    const path = join(directory, "report.json");
    const report: SeedReport = {
      stored: 2,
      alreadyPresent: 1,
      skipped: [{ id: "track-404", reason: "404 after 3 retries" }],
      failed: [{ id: "track-500", reason: "500 Internal Server Error" }],
    };

    await writeReport(path, report);

    const written: unknown = JSON.parse(await readFile(path, "utf8"));
    expect(written).toEqual(report);
  });
});
