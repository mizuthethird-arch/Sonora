import type { Server } from "node:http";
import { createApp } from "./app.js";

const shutdownSignals = ["SIGTERM", "SIGINT"] as const;

export function startServer(port: number): Promise<Server> {
  return new Promise((resolve, reject) => {
    const server = createApp().listen(port);
    server.once("listening", () => resolve(server));
    server.once("error", reject);
  });
}

export function stopServer(server: Server): Promise<void> {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}

export function shutdownOnSignals(server: Server): Promise<void> {
  return new Promise((resolve, reject) => {
    const shutdown = () => {
      removeShutdownListeners(shutdown);
      stopServer(server).then(resolve, reject);
    };

    for (const signal of shutdownSignals) {
      process.on(signal, shutdown);
    }
  });
}

function removeShutdownListeners(listener: () => void): void {
  for (const signal of shutdownSignals) {
    process.off(signal, listener);
  }
}
