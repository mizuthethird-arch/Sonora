import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { assertDisposableHost, withDatabaseName } from "./database-url.js";

function runPrisma(args: string[], input?: string): void {
  execFileSync("pnpm", ["exec", "prisma", ...args], { input, stdio: ["pipe", "ignore", "inherit"] });
}

function dropDatabase(databaseName: string): void {
  runPrisma(["db", "execute", "--stdin"], `DROP DATABASE IF EXISTS \`${databaseName}\``);
}

function requireDatabaseUrl(): string {
  const url = process.env["DATABASE_URL"];
  if (!url) {
    throw new Error("DATABASE_URL must be set to run the database tests");
  }
  assertDisposableHost(url);
  return url;
}

function migrateOrDrop(databaseName: string): void {
  try {
    runPrisma(["migrate", "deploy"]);
  } catch (migrationError) {
    throw dropAfterFailure(databaseName, migrationError);
  }
}

function dropAfterFailure(databaseName: string, migrationError: unknown): unknown {
  try {
    dropDatabase(databaseName);
  } catch (cleanupError) {
    return new AggregateError([migrationError, cleanupError], "Migration failed and the database could not be dropped");
  }
  return migrationError;
}

/**
 * Gives every test run its own empty MySQL database with all migrations applied,
 * and drops it afterwards. The name is generated here from hex digits only.
 */
export default function setup(): () => void {
  const databaseName = `sonora_test_${randomBytes(6).toString("hex")}`;
  const databaseUrl = withDatabaseName(requireDatabaseUrl(), databaseName);
  process.env["DATABASE_URL"] = databaseUrl;

  migrateOrDrop(databaseName);

  return () => dropDatabase(databaseName);
}
