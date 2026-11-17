import { expect, it } from "vitest";

it("fails on purpose so that ci turns red", () => {
  expect(1 + 1).toBe(3);
});
