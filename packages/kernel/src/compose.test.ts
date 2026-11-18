import { describe, expect, it } from "vitest";
import { composeSections } from "./compose.js";

describe("composeSections", () => {
  it("returns every section that answers, in parallel", async () => {
    const started = Date.now();
    const page = await composeSections(
      {
        genres: () => new Promise((resolve) => setTimeout(() => resolve(["jazz"]), 100)),
        albums: () => new Promise((resolve) => setTimeout(() => resolve(["album-1"]), 100)),
      },
      1000,
    );

    expect(page.genres).toEqual({ status: "ok", data: ["jazz"] });
    expect(page.albums).toEqual({ status: "ok", data: ["album-1"] });
    expect(Date.now() - started).toBeLessThan(180);
  });

  it("marks a section that times out as unavailable and still returns the rest of the page", async () => {
    const page = await composeSections(
      {
        genres: () => Promise.resolve(["jazz"]),
        recommendations: () => new Promise<never>(() => undefined),
      },
      50,
    );

    expect(page.genres).toEqual({ status: "ok", data: ["jazz"] });
    expect(page.recommendations).toEqual({ status: "unavailable", reason: "timeout" });
  });

  it("marks a section that fails as unavailable instead of failing the page", async () => {
    const page = await composeSections(
      {
        genres: () => Promise.resolve(["jazz"]),
        history: () => Promise.reject(new Error("facade down")),
      },
      1000,
    );

    expect(page.history).toEqual({ status: "unavailable", reason: "error" });
    expect(page.genres).toEqual({ status: "ok", data: ["jazz"] });
  });
});
