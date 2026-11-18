import { isPlainId } from "./request-id.js";

export type UserRef = { readonly id: string };
export type ProfileRef = { readonly id: string };

export type RequestContext = Readonly<{
  correlationId: string;
  user: UserRef | null;
  profile: ProfileRef | null;
  permissions: ReadonlySet<string>;
}>;

// Every facade method takes the caller's context first, so no call can skip the identity it needs.
export type FacadeMethod<Input, Output> = (context: RequestContext, input: Input) => Promise<Output>;

export type CreateRequestContextInput = {
  correlationId: string;
  user?: UserRef;
  profile?: ProfileRef;
  permissions?: readonly string[];
};

export function createRequestContext(input: CreateRequestContextInput): RequestContext {
  if (!isPlainId(input.correlationId)) {
    throw new Error("correlationId must be a plain identifier");
  }
  return Object.freeze({
    correlationId: input.correlationId,
    user: input.user ?? null,
    profile: input.profile ?? null,
    permissions: new Set(input.permissions ?? []),
  });
}
