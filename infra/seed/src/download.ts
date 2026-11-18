import type { DownloadResult } from "./seed.ts";

const DOWNLOAD_TIMEOUT_MS = 60_000;

// Rejects when the server does not answer within timeoutMs.
export async function fetchDownload(url: string, timeoutMs: number = DOWNLOAD_TIMEOUT_MS): Promise<DownloadResult> {
  const response = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
  const body = new Uint8Array(await response.arrayBuffer());
  return { status: response.status, body };
}
