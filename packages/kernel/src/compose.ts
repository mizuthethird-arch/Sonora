export type SectionResult<Data> =
  | { readonly status: "ok"; readonly data: Data }
  | { readonly status: "unavailable"; readonly reason: "timeout" | "error" };

export type SectionLoaders = Readonly<Record<string, () => Promise<unknown>>>;

export type ComposedPage<Loaders extends SectionLoaders> = {
  readonly [Name in keyof Loaders]: SectionResult<Awaited<ReturnType<Loaders[Name]>>>;
};

// Loads every section at once. A section that is slow, or fails, is marked unavailable, so one facade
// cannot take the whole page down with it. Nothing here throws.
export async function composeSections<Loaders extends SectionLoaders>(
  loaders: Loaders,
  timeoutMs: number,
): Promise<ComposedPage<Loaders>> {
  const entries = await Promise.all(
    Object.entries(loaders).map(async ([name, load]) => [name, await loadSection(load, timeoutMs)] as const),
  );
  return Object.fromEntries(entries) as ComposedPage<Loaders>;
}

async function loadSection(load: () => Promise<unknown>, timeoutMs: number): Promise<SectionResult<unknown>> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<SectionResult<unknown>>((resolve) => {
    timer = setTimeout(() => resolve({ status: "unavailable", reason: "timeout" }), timeoutMs);
  });
  const attempt = load().then(
    (data): SectionResult<unknown> => ({ status: "ok", data }),
    (): SectionResult<unknown> => ({ status: "unavailable", reason: "error" }),
  );
  try {
    return await Promise.race([attempt, deadline]);
  } finally {
    clearTimeout(timer);
  }
}
