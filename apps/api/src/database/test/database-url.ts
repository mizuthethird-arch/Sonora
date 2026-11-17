const DISPOSABLE_HOSTS = ["mysql", "localhost", "127.0.0.1"];
const REFUSAL_MESSAGE = "Refusing to run database tests: DATABASE_URL must point at mysql, localhost or 127.0.0.1";

export function withDatabaseName(url: string, databaseName: string): string {
  const databaseUrl = new URL(url);
  databaseUrl.pathname = `/${databaseName}`;
  return databaseUrl.toString();
}

export function assertDisposableHost(url: string): void {
  if (!URL.canParse(url) || !DISPOSABLE_HOSTS.includes(new URL(url).hostname)) {
    throw new Error(REFUSAL_MESSAGE);
  }
}
