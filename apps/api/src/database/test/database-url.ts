const DISPOSABLE_HOSTS = ["mysql", "localhost", "127.0.0.1"];
const REFUSAL_MESSAGE = "Refusing to run database tests: DATABASE_URL must point at mysql, localhost or 127.0.0.1";

export function withDatabaseName(url: string, databaseName: string): string {
  const databaseUrl = new URL(url);
  databaseUrl.pathname = `/${databaseName}`;
  return databaseUrl.toString();
}

export function assertDisposableHost(url: string): void {
  const databaseUrl = parseUrl(url);

  if (!databaseUrl || !isDisposable(databaseUrl)) {
    throw new Error(REFUSAL_MESSAGE);
  }
}

function parseUrl(url: string): URL | null {
  try {
    return new URL(url);
  } catch {
    return null;
  }
}

function isDisposable(databaseUrl: URL): boolean {
  return (
    databaseUrl.protocol === "mysql:" &&
    DISPOSABLE_HOSTS.includes(databaseUrl.hostname) &&
    databaseUrl.password === "" &&
    databaseUrl.search === ""
  );
}
