import { describe, expect, it } from "vitest";
import { parseManifest, type Track } from "./manifest.ts";

const validTrack: Track = {
  id: "track-001",
  title: "Morning Light",
  artist: "Test Artist",
  licenseCode: "CC0-1.0",
  sourcePageUrl: "https://example.org/tracks/001",
  downloadUrl: "https://example.org/files/001.mp3",
  sha256: "a".repeat(64),
};

describe("parseManifest", () => {
  it("returns an empty list when the manifest has no tracks", () => {
    expect(parseManifest([])).toEqual([]);
  });

  it("accepts a valid list of tracks", () => {
    expect(parseManifest([validTrack])).toEqual([validTrack]);
  });

  it("rejects text input that is not an array", () => {
    expect(() => parseManifest("track-001")).toThrow();
  });

  it("rejects a sha256 that is not 64 lowercase hex characters", () => {
    expect(() => parseManifest([{ ...validTrack, sha256: "A".repeat(64) }])).toThrow();
    expect(() => parseManifest([{ ...validTrack, sha256: "a".repeat(63) }])).toThrow();
  });

  it("rejects duplicate track ids", () => {
    const duplicate = { ...validTrack, title: "Another Title" };
    expect(() => parseManifest([validTrack, duplicate])).toThrow();
  });

  it("rejects a downloadUrl or sourcePageUrl that is not http or https", () => {
    expect(() => parseManifest([{ ...validTrack, downloadUrl: "ftp://example.org/001.mp3" }])).toThrow();
    expect(() => parseManifest([{ ...validTrack, sourcePageUrl: "javascript:alert(1)" }])).toThrow();
  });

  it("rejects an empty licenseCode", () => {
    expect(() => parseManifest([{ ...validTrack, licenseCode: "" }])).toThrow();
  });

  it("keeps hostile and unicode text in title and artist as plain data", () => {
    const hostile: Track = {
      ...validTrack,
      title: "Night 🌙 Drive",
      artist: "'; DROP TABLE x; --",
    };
    expect(parseManifest([hostile])).toEqual([hostile]);
  });
});
