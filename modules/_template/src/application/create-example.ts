import { type RequestContext } from "@sonora/kernel";
import { type Example, parseExampleTitle } from "../domain/example.js";

export const PERMISSION_WRITE_EXAMPLE = "template:example:write";

export type ExampleRepository = {
  save: (example: Example) => Promise<void>;
};

export type CreateExampleDeps = {
  readonly repository: ExampleRepository;
  readonly newId: () => string;
};

export type CreateExampleInput = {
  readonly title: string;
};

// The permission is checked first, so an unauthorised caller learns nothing about the input rules.
export async function createExample(
  context: RequestContext,
  input: CreateExampleInput,
  deps: CreateExampleDeps,
): Promise<Example> {
  if (!context.permissions.has(PERMISSION_WRITE_EXAMPLE)) {
    throw new Error(`missing permission ${PERMISSION_WRITE_EXAMPLE}`);
  }
  const example: Example = { id: deps.newId(), title: parseExampleTitle(input.title) };
  await deps.repository.save(example);
  return example;
}
