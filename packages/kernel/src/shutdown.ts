export type Drain = {
  readonly name: string;
  readonly drain: () => Promise<void>;
};

export type ShutdownOutcome = "drained" | "failed" | "timed-out";

export const SHUTDOWN_TIMEOUT_MS = 20000;

// Runs every drain at once (HTTP, consumers, jobs) and waits for all of them, up to the deadline.
// One failing drain does not stop the others.
export async function runGracefulShutdown(
  drains: readonly Drain[],
  timeoutMs: number = SHUTDOWN_TIMEOUT_MS,
): Promise<ShutdownOutcome> {
  const settled = Promise.allSettled(drains.map((item) => Promise.resolve().then(() => item.drain())));
  const results = await untilDeadline(settled, timeoutMs);

  if (results === undefined) {
    return "timed-out";
  }
  return results.every((result) => result.status === "fulfilled") ? "drained" : "failed";
}

async function untilDeadline<Value>(work: Promise<Value>, timeoutMs: number): Promise<Value | undefined> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<undefined>((resolve) => {
    timer = setTimeout(() => resolve(undefined), timeoutMs);
  });
  try {
    return await Promise.race([work, deadline]);
  } finally {
    clearTimeout(timer);
  }
}
