import { describe, expect, it } from "vitest";
import { z } from "zod";
import { bootConfig, loadConfig } from "./config.js";

const schema = z.object({
  DATABASE_URL: z.url(),
  RABBITMQ_URL: z.url(),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
});

const complete = {
  DATABASE_URL: "mysql://identity_user:not-a-real-password@mysql:3306/identity",
  RABBITMQ_URL: "amqp://sonora:not-a-real-password@rabbitmq:5672",
};

describe("loadConfig", () => {
  it("returns the parsed values when every key is present", () => {
    const config = loadConfig(schema, { ...complete, PORT: "8080" });

    expect(config).toEqual({ ...complete, PORT: 8080 });
  });

  it("names DATABASE_URL when it is absent", () => {
    expect(() => loadConfig(schema, { RABBITMQ_URL: complete.RABBITMQ_URL })).toThrow(/DATABASE_URL/);
  });

  it("names both keys when both are absent", () => {
    expect(() => loadConfig(schema, {})).toThrow(/DATABASE_URL.*RABBITMQ_URL|RABBITMQ_URL.*DATABASE_URL/);
  });

  it("never prints a secret value in its error", () => {
    const leaked = "super-secret-broker-password";

    try {
      loadConfig(schema, { DATABASE_URL: complete.DATABASE_URL, RABBITMQ_URL: `not a url ${leaked}` });
      expect.fail("loadConfig should have thrown");
    } catch (error) {
      expect(String(error)).toMatch(/RABBITMQ_URL/);
      expect(String(error)).not.toContain(leaked);
    }
  });
});

describe("bootConfig", () => {
  it("exits with code 1 and lists the missing keys when DATABASE_URL or RABBITMQ_URL is absent", () => {
    const exits: number[] = [];
    const logs: string[] = [];

    const config = bootConfig(schema, { RABBITMQ_URL: complete.RABBITMQ_URL }, {
      exit: (code) => exits.push(code),
      log: (message) => logs.push(message),
    });

    expect(config).toBeUndefined();
    expect(exits).toEqual([1]);
    expect(logs.join("\n")).toMatch(/DATABASE_URL/);
  });

  it("returns the config without exiting when every key is present", () => {
    const exits: number[] = [];

    const config = bootConfig(schema, complete, { exit: (code) => exits.push(code), log: () => undefined });

    expect(config?.DATABASE_URL).toBe(complete.DATABASE_URL);
    expect(exits).toEqual([]);
  });
});
