import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";

function runPrisma(args: string[], input?: string): void {
  execFileSync("pnpm", ["exec", "prisma", ...args], { input, stdio: ["pipe", "ignore", "inherit"] });
}

function withDatabaseName(url: string, databaseName: string): string {
  const databaseUrl = new URL(url);
  databaseUrl.pathname = `/${databaseName}`;
  return databaseUrl.toString();
}

function requireDatabaseUrl(): string {
  const url = process.env["DATABASE_URL"];
  if (!url) {
    throw new Error("DATABASE_URL must be set to run the database tests");
  }
  return url;
}

/**
 * Gives every test run its own empty MySQL database with all migrations applied,
 * and drops it afterwards. The name is generated here from hex digits only.
 */
export default function setup(): () => void {
  const databaseName = `sonora_test_${randomBytes(6).toString("hex")}`;
  process.env["DATABASE_URL"] = withDatabaseName(requireDatabaseUrl(), databaseName);

  runPrisma(["migrate", "deploy"]);

  return () => runPrisma(["db", "execute", "--stdin"], `DROP DATABASE \`${databaseName}\``);
}
