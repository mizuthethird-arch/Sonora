import { Writable } from "node:stream";
import { describe, expect, it } from "vitest";
import { createLogger } from "./logger.js";

function captureLines(): { stream: Writable; lines: () => string[] } {
  const chunks: string[] = [];
  const stream = new Writable({
    write(chunk: Buffer, _encoding, callback) {
      chunks.push(chunk.toString());
      callback();
    },
  });
  return { stream, lines: () => chunks.join("").split("\n").filter(Boolean) };
}

describe("createLogger", () => {
  it("redacts authorization, cookie and password fields", () => {
    const output = captureLines();
    const logger = createLogger({ destination: output.stream });

    logger.info({ req: { headers: { authorization: "Bearer secret-token", cookie: "session=abc" } }, password: "hunter2" }, "request");

    const [line] = output.lines();
    expect(line).not.toContain("secret-token");
    expect(line).not.toContain("session=abc");
    expect(line).not.toContain("hunter2");
    expect(line).toContain("[Redacted]");
  });

  it("writes JSON lines", () => {
    const output = captureLines();
    const logger = createLogger({ destination: output.stream });

    logger.info("started");

    expect(JSON.parse(output.lines()[0] ?? "{}")).toMatchObject({ msg: "started" });
  });
});
