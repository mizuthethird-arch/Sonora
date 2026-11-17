import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, describe, expect, it } from "vitest";
import { shutdownOnSignals, startServer, stopServer } from "./server.js";

const startedServers: Server[] = [];

async function startOnFreePort(): Promise<Server> {
  const server = await startServer(0);
  startedServers.push(server);
  return server;
}

function portOf(server: Server): number {
  const address = server.address() as AddressInfo;
  return address.port;
}

afterEach(async () => {
  for (const server of startedServers.splice(0)) {
    if (server.listening) {
      await stopServer(server);
    }
  }
});

describe("startServer", () => {
  it("listens and serves GET /health over a real socket", async () => {
    const server = await startOnFreePort();

    const response = await fetch(`http://127.0.0.1:${portOf(server)}/health`);

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ok" });
  });

  it("rejects when the port is already in use", async () => {
    const first = await startOnFreePort();

    await expect(startServer(portOf(first))).rejects.toThrow();
  });
});

describe("a listening server", () => {
  it("does not swallow runtime errors", async () => {
    const server = await startOnFreePort();

    expect(() => server.emit("error", new Error("runtime failure"))).toThrow("runtime failure");
  });
});

describe("stopServer", () => {
  it("stops accepting connections", async () => {
    const server = await startOnFreePort();
    const port = portOf(server);

    await stopServer(server);

    await expect(fetch(`http://127.0.0.1:${port}/health`)).rejects.toThrow();
  });

  it("finishes even when a keep-alive connection is idle", async () => {
    const server = await startOnFreePort();
    await fetch(`http://127.0.0.1:${portOf(server)}/health`);

    await expect(stopServer(server)).resolves.toBeUndefined();
  });

  it("rejects when the server is not running", async () => {
    const server = await startOnFreePort();
    await stopServer(server);

    await expect(stopServer(server)).rejects.toThrow();
  });
});

describe("shutdownOnSignals", () => {
  it("stops the server when SIGTERM is received", async () => {
    const server = await startOnFreePort();
    const port = portOf(server);
    const stopped = shutdownOnSignals(server);

    process.emit("SIGTERM");
    await stopped;

    await expect(fetch(`http://127.0.0.1:${port}/health`)).rejects.toThrow();
  });

  it("stops the server when SIGINT is received", async () => {
    const server = await startOnFreePort();
    const stopped = shutdownOnSignals(server);

    process.emit("SIGINT");
    await stopped;

    expect(server.listening).toBe(false);
  });

  it("removes its signal listeners once the server has stopped", async () => {
    const countListeners = () => process.listenerCount("SIGTERM") + process.listenerCount("SIGINT");
    const listenersBefore = countListeners();
    const server = await startOnFreePort();
    const stopped = shutdownOnSignals(server);

    process.emit("SIGTERM");
    await stopped;

    expect(countListeners()).toBe(listenersBefore);
  });
});
