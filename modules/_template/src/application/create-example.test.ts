import { createRequestContext } from "@sonora/kernel";
import { describe, expect, it } from "vitest";
import { type ExampleRepository, createExample, PERMISSION_WRITE_EXAMPLE } from "./create-example.js";

function memoryRepository(): ExampleRepository & { saved: { id: string; title: string }[] } {
  const saved: { id: string; title: string }[] = [];
  return {
    saved,
    save: (example) => {
      saved.push(example);
      return Promise.resolve();
    },
  };
}

const writer = createRequestContext({
  correlationId: "0b6f1c2e-7a3d-4f0e-9c1b-5d2e8a7f4c10",
  user: { id: "user-1" },
  permissions: [PERMISSION_WRITE_EXAMPLE],
});

const reader = createRequestContext({
  correlationId: "0b6f1c2e-7a3d-4f0e-9c1b-5d2e8a7f4c11",
  user: { id: "user-2" },
  permissions: [],
});

describe("createExample", () => {
  it("saves and returns the example when the caller has permission", async () => {
    const repository = memoryRepository();

    const example = await createExample(writer, { title: "Morning mix" }, { repository, newId: () => "ex-1" });

    expect(example).toEqual({ id: "ex-1", title: "Morning mix" });
    expect(repository.saved).toEqual([{ id: "ex-1", title: "Morning mix" }]);
  });

  it("refuses a caller without permission and saves nothing", async () => {
    const repository = memoryRepository();

    await expect(
      createExample(reader, { title: "Morning mix" }, { repository, newId: () => "ex-1" }),
    ).rejects.toThrow(/permission/);
    expect(repository.saved).toEqual([]);
  });

  it("refuses an invalid title and saves nothing", async () => {
    const repository = memoryRepository();

    await expect(createExample(writer, { title: "  " }, { repository, newId: () => "ex-1" })).rejects.toThrow();
    expect(repository.saved).toEqual([]);
  });
});
