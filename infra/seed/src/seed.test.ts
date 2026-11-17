import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import type { Track } from "./manifest.ts";
import {
  ChecksumMismatchError,
  runSeed,
  type Download,
  type DownloadResult,
  type SeedDeps,
  type Storage,
} from "./seed.ts";

type StoredObject = { body: Uint8Array; sha256: string };

class MemoryStorage implements Storage {
  readonly objects = new Map<string, StoredObject>();

  async has(key: string, sha256: string): Promise<boolean> {
    return this.objects.get(key)?.sha256 === sha256;
  }

  async put(key: string, body: Uint8Array, sha256: string): Promise<void> {
    this.objects.set(key, { body, sha256 });
  }
}

function sha256Hex(body: Uint8Array): string {
  return createHash("sha256").update(body).digest("hex");
}

function makeTrack(id: string, body: Uint8Array): Track {
  return {
    id,
    title: `Title ${id}`,
    artist: "Test Artist",
    licenseCode: "CC0-1.0",
    sourcePageUrl: `https://example.org/tracks/${id}`,
    downloadUrl: `https://example.org/files/${id}.mp3`,
    sha256: sha256Hex(body),
  };
}

// Each URL maps to a queue of scripted responses; every call is recorded in `calls`.
function makeDownload(script: Record<string, DownloadResult[]>): { download: Download; calls: string[] } {
  const calls: string[] = [];
  const download: Download = async (url) => {
    calls.push(url);
    const next = script[url]?.shift();
    if (next === undefined) {
      throw new Error(`no scripted response left for ${url}`);
    }
    return next;
  };
  return { download, calls };
}

function makeDeps(storage: Storage, download: Download): { deps: SeedDeps; sleeps: number[] } {
  const sleeps: number[] = [];
  const deps: SeedDeps = {
    storage,
    download,
    sleep: async (milliseconds) => {
      sleeps.push(milliseconds);
    },
  };
  return { deps, sleeps };
}

const audio = new TextEncoder().encode("audio-bytes");
const otherAudio = new TextEncoder().encode("tampered-bytes");
const notFound: DownloadResult = { status: 404, body: new Uint8Array() };
const tooManyRequests: DownloadResult = { status: 429, body: new Uint8Array() };
const serverError: DownloadResult = { status: 500, body: new Uint8Array() };

describe("runSeed", () => {
  it("returns zero counts for an empty manifest", async () => {
    const { deps, sleeps } = makeDeps(new MemoryStorage(), makeDownload({}).download);

    const report = await runSeed([], deps);

    expect(report).toEqual({ stored: 0, alreadyPresent: 0, skipped: [], failed: [] });
    expect(sleeps).toEqual([]);
  });

  it("throws ChecksumMismatchError naming the track id, stores nothing for it, and stops the run", async () => {
    const storage = new MemoryStorage();
    const bad = makeTrack("track-bad", audio);
    const good = makeTrack("track-good", audio);
    const { download, calls } = makeDownload({
      [bad.downloadUrl]: [{ status: 200, body: otherAudio }],
      [good.downloadUrl]: [{ status: 200, body: audio }],
    });
    const { deps } = makeDeps(storage, download);

    const outcome = runSeed([bad, good], deps);

    await expect(outcome).rejects.toBeInstanceOf(ChecksumMismatchError);
    await expect(outcome).rejects.toThrow("track-bad");
    expect(storage.objects.has("track-bad")).toBe(false);
    expect(calls).toEqual([bad.downloadUrl]);
  });

  it("retries a 404 three times with backoff, then skips it and continues with the next track", async () => {
    const storage = new MemoryStorage();
    const missing = makeTrack("track-404", audio);
    const good = makeTrack("track-good", audio);
    const { download, calls } = makeDownload({
      [missing.downloadUrl]: Array.from({ length: 4 }, () => notFound),
      [good.downloadUrl]: [{ status: 200, body: audio }],
    });
    const { deps, sleeps } = makeDeps(storage, download);

    const report = await runSeed([missing, good], deps);

    expect(calls.filter((url) => url === missing.downloadUrl)).toHaveLength(4);
    expect(sleeps).toEqual([1000, 2000, 4000]);
    expect(report.skipped).toEqual([{ id: "track-404", reason: expect.stringContaining("404") }]);
    expect(report.stored).toBe(1);
    expect(storage.objects.has("track-good")).toBe(true);
  });

  it("stores a track after a 429 followed by a 200, with one sleep of 1000 milliseconds", async () => {
    const storage = new MemoryStorage();
    const track = makeTrack("track-busy", audio);
    const { download } = makeDownload({
      [track.downloadUrl]: [tooManyRequests, { status: 200, body: audio }],
    });
    const { deps, sleeps } = makeDeps(storage, download);

    const report = await runSeed([track], deps);

    expect(report.stored).toBe(1);
    expect(storage.objects.has("track-busy")).toBe(true);
    expect(sleeps).toEqual([1000]);
  });

  it("skips a track after a 429 that never clears, following three retries", async () => {
    const track = makeTrack("track-stuck", audio);
    const { download, calls } = makeDownload({
      [track.downloadUrl]: Array.from({ length: 4 }, () => tooManyRequests),
    });
    const { deps, sleeps } = makeDeps(new MemoryStorage(), download);

    const report = await runSeed([track], deps);

    expect(calls).toHaveLength(4);
    expect(sleeps).toEqual([1000, 2000, 4000]);
    expect(report.skipped).toEqual([{ id: "track-stuck", reason: expect.stringContaining("429") }]);
  });

  it("records a 500 in failed without any retry", async () => {
    const track = makeTrack("track-broken", audio);
    const { download, calls } = makeDownload({
      [track.downloadUrl]: [serverError],
    });
    const { deps, sleeps } = makeDeps(new MemoryStorage(), download);

    const report = await runSeed([track], deps);

    expect(calls).toHaveLength(1);
    expect(sleeps).toEqual([]);
    expect(report.failed).toEqual([{ id: "track-broken", reason: expect.stringContaining("500") }]);
    expect(report.skipped).toEqual([]);
  });

  it("skips a track whose object already exists without downloading it", async () => {
    const storage = new MemoryStorage();
    const track = makeTrack("track-001", audio);
    await storage.put(track.id, audio, track.sha256);
    const { download, calls } = makeDownload({});
    const { deps } = makeDeps(storage, download);

    const report = await runSeed([track], deps);

    expect(report.alreadyPresent).toBe(1);
    expect(report.stored).toBe(0);
    expect(calls).toEqual([]);
  });

  it("stores nothing on a second run over the same manifest", async () => {
    const storage = new MemoryStorage();
    const first = makeTrack("track-001", audio);
    const second = makeTrack("track-002", otherAudio);
    const { download, calls } = makeDownload({
      [first.downloadUrl]: [{ status: 200, body: audio }],
      [second.downloadUrl]: [{ status: 200, body: otherAudio }],
    });
    const { deps } = makeDeps(storage, download);
    await runSeed([first, second], deps);
    const downloadsAfterFirstRun = calls.length;

    const report = await runSeed([first, second], deps);

    expect(report).toEqual({ stored: 0, alreadyPresent: 2, skipped: [], failed: [] });
    expect(calls).toHaveLength(downloadsAfterFirstRun);
  });

  it("stores a new track under the key equal to the track id and counts it as stored", async () => {
    const storage = new MemoryStorage();
    const track = makeTrack("track-001", audio);
    const { download } = makeDownload({
      [track.downloadUrl]: [{ status: 200, body: audio }],
    });
    const { deps } = makeDeps(storage, download);

    const report = await runSeed([track], deps);

    expect(report.stored).toBe(1);
    expect(report.alreadyPresent).toBe(0);
    expect(storage.objects.get("track-001")?.body).toEqual(audio);
  });

  it("computes the sha256 with node:crypto over the downloaded body", async () => {
    const storage = new MemoryStorage();
    const track = makeTrack("track-001", audio);
    const { download } = makeDownload({
      [track.downloadUrl]: [{ status: 200, body: audio }],
    });
    const { deps } = makeDeps(storage, download);

    await runSeed([track], deps);

    expect(storage.objects.get("track-001")?.sha256).toBe(createHash("sha256").update(audio).digest("hex"));
  });
});
