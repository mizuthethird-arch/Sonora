import { type z } from "zod";
import { KernelStatusOk, KernelStatusUnavailable, kernelRouteGroup } from "../routes/kernel.js";
import { type RouteContract } from "../routes/route-group.js";

export type FetchLike = (input: string | URL) => Promise<Response>;

export type ContractsClientOptions = {
  readonly baseUrl: string;
  readonly fetch?: FetchLike;
};

// Every response is parsed with the schema its route declares for that status. A status the route does not
// declare, or a body that does not match, is an error. Nothing is trusted unparsed.
export function createContractsClient(options: ContractsClientOptions) {
  const fetchImpl: FetchLike = options.fetch ?? ((input) => fetch(input));

  async function call(path: string): Promise<unknown> {
    const route = findRoute(path);
    const response = await fetchImpl(new URL(path, options.baseUrl));
    const schema = route.responses[response.status];
    if (schema === undefined) {
      throw new Error(`unexpected status ${response.status} from GET ${path}`);
    }
    const parsed = schema.safeParse(await response.json());
    if (!parsed.success) {
      throw new Error(`response from GET ${path} does not match its contract`);
    }
    return parsed.data;
  }

  return {
    liveness: async (): Promise<z.infer<typeof KernelStatusOk>> =>
      (await call("/health/live")) as z.infer<typeof KernelStatusOk>,
    readiness: async (): Promise<z.infer<typeof KernelStatusOk> | z.infer<typeof KernelStatusUnavailable>> =>
      (await call("/health/ready")) as z.infer<typeof KernelStatusOk> | z.infer<typeof KernelStatusUnavailable>,
  };
}

function findRoute(path: string): RouteContract {
  const route = kernelRouteGroup.routes.find((candidate) => candidate.path === path && candidate.method === "get");
  if (route === undefined) {
    throw new Error(`no GET route ${path} in the contracts`);
  }
  return route;
}
