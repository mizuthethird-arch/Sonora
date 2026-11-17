import { once } from "node:events";
import type { Server } from "node:http";
import { promisify } from "node:util";
import { createApp } from "./app.js";

const shutdownSignals = ["SIGTERM", "SIGINT"] as const;

export async function startServer(port: number): Promise<Server> {
  const server = createApp().listen(port);
  await once(server, "listening");
  return server;
}

export function stopServer(server: Server): Promise<void> {
  return promisify(server.close.bind(server))();
}

export async function shutdownOnSignals(server: Server): Promise<void> {
  await waitForShutdownSignal();
  await stopServer(server);
}

function waitForShutdownSignal(): Promise<void> {
  return new Promise((resolve) => {
    const onSignal = () => {
      removeShutdownListeners(onSignal);
      resolve();
    };

    for (const signal of shutdownSignals) {
      process.on(signal, onSignal);
    }
  });
}

function removeShutdownListeners(listener: () => void): void {
  for (const signal of shutdownSignals) {
    process.off(signal, listener);
  }
}
