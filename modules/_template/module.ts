import { defineModule, type RequestContext } from "@sonora/kernel";
import { type CreateExampleDeps, type CreateExampleInput, createExample } from "./src/application/create-example.js";
import { type Example } from "./src/domain/example.js";

export function templateModule(deps: CreateExampleDeps) {
  return defineModule({
    name: "template",
    routePrefix: "/template",
    routes: () => undefined,
    consumers: [],
    jobs: [],
    facade: {
      createExample: (context: RequestContext, input: CreateExampleInput): Promise<Example> =>
        createExample(context, input, deps),
    },
  });
}
