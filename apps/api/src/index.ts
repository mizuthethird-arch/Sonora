import { loadConfig } from "./config.js";
import { shutdownOnSignals, startServer } from "./server.js";

const config = loadConfig(process.env);
const server = await startServer(config.port, { webOrigin: config.webOrigin });

await shutdownOnSignals(server);
