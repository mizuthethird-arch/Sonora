import { readFile } from "node:fs/promises";
import { z } from "zod";
import { fetchDownload } from "./download.ts";
import { parseManifest } from "./manifest.ts";
import { writeReport } from "./report.ts";
import { createS3Storage } from "./s3-storage.ts";
import { runSeed, type SeedReport } from "./seed.ts";

const EnvSchema = z.object({
  S3_ENDPOINT: z.string({ error: "S3_ENDPOINT is required" }).min(1, "S3_ENDPOINT is required"),
  S3_BUCKET: z.string().min(1).default("originals"),
  AWS_REGION: z.string().min(1).default("us-east-1"),
  MANIFEST_PATH: z.string().min(1).default("manifest.json"),
  SEED_REPORT_PATH: z.string().min(1).default("seed-report.json"),
});

type Env = z.infer<typeof EnvSchema>;

function readEnv(environment: NodeJS.ProcessEnv): Env {
  const parsed = EnvSchema.safeParse(environment);
  if (!parsed.success) {
    throw new Error(z.prettifyError(parsed.error));
  }
  return parsed.data;
}

function sleep(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function summarize(report: SeedReport): string {
  return `stored ${report.stored}, already present ${report.alreadyPresent}, skipped ${report.skipped.length}, failed ${report.failed.length}`;
}

async function main(): Promise<number> {
  const env = readEnv(process.env);
  const manifest = parseManifest(JSON.parse(await readFile(env.MANIFEST_PATH, "utf8")));
  const storage = createS3Storage({ endpoint: env.S3_ENDPOINT, bucket: env.S3_BUCKET, region: env.AWS_REGION });
  const report = await runSeed(manifest, { storage, download: fetchDownload, sleep });
  await writeReport(env.SEED_REPORT_PATH, report);
  console.log(summarize(report));
  return report.failed.length > 0 ? 1 : 0;
}

// The only place errors are handled: print the message and exit 1.
main().then(
  (code) => {
    process.exitCode = code;
  },
  (error: unknown) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  },
);
