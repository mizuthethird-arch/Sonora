import { describe, expect, it } from "vitest";
import { loadConfig } from "./config.js";

describe("loadConfig", () => {
  it("uses port 3000 when PORT is not set", () => {
    expect(loadConfig({})).toEqual({ port: 3000 });
  });

  it("reads the port from PORT", () => {
    expect(loadConfig({ PORT: "8080" })).toEqual({ port: 8080 });
  });

  it("accepts the lowest and highest valid ports", () => {
    expect(loadConfig({ PORT: "1" }).port).toBe(1);
    expect(loadConfig({ PORT: "65535" }).port).toBe(65535);
  });

  it.each([
    ["empty", ""],
    ["blank", "   "],
    ["zero", "0"],
    ["too high", "65536"],
    ["negative", "-1"],
    ["decimal", "3.5"],
    ["exponent", "1e3"],
    ["trailing text", "3000abc"],
    ["not a number", "abc"],
    ["hostile characters", "3000; rm -rf /"],
  ])("rejects a PORT that is %s", (_name, port) => {
    expect(() => loadConfig({ PORT: port })).toThrow("Invalid configuration");
  });

  it("does not echo the rejected value in the error", () => {
    expect(() => loadConfig({ PORT: "secret-looking-value" })).toThrow(/^(?!.*secret-looking-value)/);
  });
});
