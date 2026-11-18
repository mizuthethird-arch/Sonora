import { loadConfig } from "./config.js";
import { shutdownOnSignals, startServer } from "./server.js";

const config = loadConfig(process.env);
const server = await startServer(config.port, {
  webOrigin: config.webOrigin,
  nodeEnv: process.env["NODE_ENV"],
});

await shutdownOnSignals(server);
