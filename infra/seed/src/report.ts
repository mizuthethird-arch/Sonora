import { writeFile } from "node:fs/promises";
import type { SeedReport } from "./seed.ts";

export async function writeReport(path: string, report: SeedReport): Promise<void> {
  await writeFile(path, `${JSON.stringify(report, null, 2)}\n`, "utf8");
}
