import { type FacadeMethod } from "@sonora/kernel";
import { type CreateExampleInput } from "../application/create-example.js";
import { type Example } from "../domain/example.js";

export type { CreateExampleInput, ExampleRepository } from "../application/create-example.js";
export type { Example } from "../domain/example.js";

export type TemplateFacade = {
  readonly createExample: FacadeMethod<CreateExampleInput, Example>;
};
