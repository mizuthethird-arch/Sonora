import { createClient } from "redis";
import { loadConfig } from "./config.js";
import { createRedisRateLimitStore } from "./redis/rate-limit-store.js";
import { shutdownOnSignals, startServer } from "./server.js";

const config = loadConfig(process.env);

// Without REDIS_URL, rate-limit counters stay in memory for this process.
const redis = config.redisUrl !== undefined ? createClient({ url: config.redisUrl }) : undefined;
await redis?.connect();

const server = await startServer(config.port, {
  webOrigin: config.webOrigin,
  nodeEnv: process.env["NODE_ENV"],
  trustProxyHops: config.trustProxyHops,
  rateLimitStore:
    redis === undefined ? undefined : (scope) => createRedisRateLimitStore(redis, `sonora:ratelimit:${scope}:`),
});

await shutdownOnSignals(server);
await redis?.quit();
