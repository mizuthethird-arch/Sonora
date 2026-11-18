export type ReadinessCheck = () => Promise<void>;

export const READINESS_TIMEOUT_MS = 2000;

// Ready only when every check passes within the timeout. A check that rejects or hangs makes the process not ready.
export async function runReadinessChecks(
  checks: Record<string, ReadinessCheck>,
  timeoutMs: number = READINESS_TIMEOUT_MS,
): Promise<boolean> {
  const results = await Promise.all(Object.values(checks).map((check) => runWithTimeout(check, timeoutMs)));
  return results.every(Boolean);
}

async function runWithTimeout(check: ReadinessCheck, timeoutMs: number): Promise<boolean> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<false>((resolve) => {
    timer = setTimeout(() => resolve(false), timeoutMs);
  });
  const passed = check().then(
    () => true,
    () => false,
  );
  try {
    return await Promise.race([passed, timeout]);
  } finally {
    clearTimeout(timer);
  }
}
