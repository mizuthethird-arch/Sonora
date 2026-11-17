import { describe, expect, it } from "vitest";
import { assertDisposableHost, withDatabaseName } from "./database-url.js";

describe("withDatabaseName", () => {
  it("replaces only the database name", () => {
    const url = withDatabaseName("mysql://user:pass@mysql:3306/sonora", "sonora_test_ab12");

    expect(url).toBe("mysql://user:pass@mysql:3306/sonora_test_ab12");
  });
});

describe("assertDisposableHost", () => {
  it.each(["mysql", "localhost", "127.0.0.1"])("accepts the test host %s", (host) => {
    expect(() => assertDisposableHost(`mysql://root@${host}:3306/sonora`)).not.toThrow();
  });

  it.each([
    ["a shared database", "mysql://root@db.example.com:3306/sonora"],
    ["a lookalike host", "mysql://root@mysql.evil.com:3306/sonora"],
    ["a managed database", "mysql://admin:secret@sonora.abc123.eu-west-1.rds.amazonaws.com:3306/sonora"],
  ])("refuses %s", (_name, url) => {
    expect(() => assertDisposableHost(url)).toThrow("Refusing to run database tests");
  });

  it.each([
    ["a host option in the query", "mysql://root@mysql:3306/sonora?host=db.example.com"],
    ["a socket option in the query", "mysql://root@mysql:3306/sonora?socketPath=/tmp/shared.sock"],
    ["another protocol", "postgres://root@mysql:3306/sonora"],
    ["a password", "mysql://root:secret@mysql:3306/sonora"],
    ["a different host written as user", "mysql://mysql@db.example.com:3306/sonora"],
  ])("refuses %s", (_name, url) => {
    expect(() => assertDisposableHost(url)).toThrow("Refusing to run database tests");
  });

  it("accepts a user name that only looks like a host", () => {
    expect(() => assertDisposableHost("mysql://db.example.com@mysql:3306/sonora")).not.toThrow();
  });

  it("refuses text that is not a URL", () => {
    expect(() => assertDisposableHost("not a url")).toThrow("Refusing to run database tests");
  });

  it("never repeats the credentials in the error", () => {
    expect(() => assertDisposableHost("mysql://admin:secret@db.example.com:3306/sonora")).toThrow(
      new Error("Refusing to run database tests: DATABASE_URL must point at mysql, localhost or 127.0.0.1"),
    );
  });
});
