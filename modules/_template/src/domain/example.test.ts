import { describe, expect, it } from "vitest";
import { MAX_TITLE_LENGTH, parseExampleTitle } from "./example.js";

describe("parseExampleTitle", () => {
  it("trims surrounding spaces and keeps the title", () => {
    expect(parseExampleTitle("  Morning mix  ")).toBe("Morning mix");
  });

  it("refuses an empty title", () => {
    expect(() => parseExampleTitle("   ")).toThrow();
  });

  it("refuses a title over the maximum length", () => {
    expect(() => parseExampleTitle("a".repeat(MAX_TITLE_LENGTH + 1))).toThrow();
  });

  it("accepts a title of exactly the maximum length", () => {
    expect(parseExampleTitle("a".repeat(MAX_TITLE_LENGTH))).toHaveLength(MAX_TITLE_LENGTH);
  });

  it("refuses control characters", () => {
    expect(() => parseExampleTitle("bad\u0000title")).toThrow();
  });
});
