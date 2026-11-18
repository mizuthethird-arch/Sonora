import { describe, expect, it } from "vitest";
import { runInTransaction, type TransactionalDatabase } from "./transaction.js";

function fakeDatabase(events: string[]): TransactionalDatabase<string> {
  return {
    moduleDatabase: "catalog",
    begin: () => {
      events.push("begin");
      return Promise.resolve("tx-handle");
    },
    commit: () => {
      events.push("commit");
      return Promise.resolve();
    },
    rollback: () => {
      events.push("rollback");
      return Promise.resolve();
    },
  };
}

describe("runInTransaction", () => {
  it("commits and returns the value when the work succeeds", async () => {
    const events: string[] = [];

    const result = await runInTransaction(fakeDatabase(events), (tx) => {
      events.push(`work:${tx}`);
      return Promise.resolve(42);
    });

    expect(result).toBe(42);
    expect(events).toEqual(["begin", "work:tx-handle", "commit"]);
  });

  it("rolls back and rethrows the original error when the work fails", async () => {
    const events: string[] = [];
    const failure = new Error("constraint violated");

    await expect(
      runInTransaction(fakeDatabase(events), () => Promise.reject(failure)),
    ).rejects.toBe(failure);

    expect(events).toEqual(["begin", "rollback"]);
  });

  it("reports the module database it is scoped to", () => {
    expect(fakeDatabase([]).moduleDatabase).toBe("catalog");
  });
});
