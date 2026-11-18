import { RedisStore } from "rate-limit-redis";

// The part of a node-redis client the store needs: a raw command, given as its words.
export type RedisCommandClient = {
  readonly sendCommand: (words: string[]) => Promise<unknown>;
};

// A Redis-backed store for express-rate-limit. The prefix keeps this application's counters apart from other keys.
export function createRedisRateLimitStore(client: RedisCommandClient, prefix: string): RedisStore {
  return new RedisStore({
    prefix,
    sendCommand: (...words: string[]) => client.sendCommand(words) as Promise<never>,
  });
}
