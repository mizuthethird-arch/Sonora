import { describe, expect, it } from "vitest";
import { findForbiddenExports } from "./public-entry.js";

describe("findForbiddenExports", () => {
  it.each([
    ["an empty export", "export {};"],
    ["an interface", "export interface CatalogFacade { readonly name: string }"],
    ["a type alias", "export type TrackId = string;"],
    ["a type-only re-export", 'export type { CatalogFacade } from "./facade.js";'],
    ["an inline type-only re-export", 'export { type CatalogFacade } from "./facade.js";'],
    ["an event schema", "export const TrackAddedEventSchema = z.object({});"],
    ["an event schema re-export", 'export { TrackAddedEventSchema } from "./events.js";'],
    ["imports and private code", 'import { z } from "zod";\nconst hidden = 1;\nexport type Hidden = typeof hidden;'],
  ])("allows %s", (_name, source) => {
    expect(findForbiddenExports(source)).toEqual([]);
  });

  it.each([
    ["a function", "export function helper(): void {}"],
    ["a class", "export class Service {}"],
    ["an enum", "export enum Kind { A }"],
    ["a plain constant", "export const helper = 1;"],
    ["a default export", "export default 1;"],
    ["a star re-export", 'export * from "./internal.js";'],
    ["a named star re-export", 'export * as internal from "./internal.js";'],
    ["a value re-export", 'export { helper } from "./internal.js";'],
  ])("reports %s", (_name, source) => {
    expect(findForbiddenExports(source)).toHaveLength(1);
  });

  it("reports every forbidden export in a file", () => {
    const source = "export function a(): void {}\nexport class B {}\nexport interface Fine {}";

    expect(findForbiddenExports(source)).toHaveLength(2);
  });
});
