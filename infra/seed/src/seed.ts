import { createHash } from "node:crypto";
import type { Track } from "./manifest.ts";

export type DownloadResult = { status: number; body: Uint8Array };

export type Download = (url: string) => Promise<DownloadResult>;

export interface Storage {
  has(key: string, sha256: string): Promise<boolean>;
  put(key: string, body: Uint8Array, sha256: string): Promise<void>;
}

export type SeedDeps = {
  storage: Storage;
  download: Download;
  sleep: (milliseconds: number) => Promise<void>;
};

// Used for both the skipped and the failed lists of the report.
export type SkippedTrack = { id: string; reason: string };

export type SeedReport = {
  stored: number;
  alreadyPresent: number;
  skipped: SkippedTrack[];
  failed: SkippedTrack[];
};

export class ChecksumMismatchError extends Error {
  readonly trackId: string;

  constructor(trackId: string, expected: string, actual: string) {
    super(`checksum mismatch for track ${trackId}: manifest sha256 ${expected}, downloaded sha256 ${actual}`);
    this.name = "ChecksumMismatchError";
    this.trackId = trackId;
  }
}

const RETRY_DELAYS_MS = [1000, 2000, 4000];
const RETRYABLE_STATUSES = [404, 429];

function isSuccess(status: number): boolean {
  return status >= 200 && status < 300;
}

function sha256Hex(body: Uint8Array): string {
  return createHash("sha256").update(body).digest("hex");
}

// Retries 404 and 429 responses with the delays above; the last attempt's result is returned as is.
async function downloadWithRetry(url: string, deps: SeedDeps): Promise<DownloadResult> {
  for (const delay of RETRY_DELAYS_MS) {
    const result = await deps.download(url);
    if (!RETRYABLE_STATUSES.includes(result.status)) {
      return result;
    }
    await deps.sleep(delay);
  }
  return deps.download(url);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

// Returns undefined and records the track in failed when the download throws; a thrown download is not retried.
async function downloadTrack(track: Track, deps: SeedDeps, report: SeedReport): Promise<DownloadResult | undefined> {
  try {
    return await downloadWithRetry(track.downloadUrl, deps);
  } catch (error) {
    report.failed.push({ id: track.id, reason: errorMessage(error) });
    return undefined;
  }
}

async function seedTrack(track: Track, deps: SeedDeps, report: SeedReport): Promise<void> {
  if (await deps.storage.has(track.id, track.sha256)) {
    report.alreadyPresent += 1;
    return;
  }
  const result = await downloadTrack(track, deps, report);
  if (result === undefined) {
    return;
  }
  if (RETRYABLE_STATUSES.includes(result.status)) {
    report.skipped.push({ id: track.id, reason: `HTTP ${result.status} after ${RETRY_DELAYS_MS.length} retries` });
    return;
  }
  if (!isSuccess(result.status)) {
    report.failed.push({ id: track.id, reason: `HTTP ${result.status}` });
    return;
  }
  const actual = sha256Hex(result.body);
  if (actual !== track.sha256) {
    throw new ChecksumMismatchError(track.id, track.sha256, actual);
  }
  await deps.storage.put(track.id, result.body, actual);
  report.stored += 1;
}

export async function runSeed(tracks: Track[], deps: SeedDeps): Promise<SeedReport> {
  const report: SeedReport = { stored: 0, alreadyPresent: 0, skipped: [], failed: [] };
  for (const track of tracks) {
    await seedTrack(track, deps, report);
  }
  return report;
}
