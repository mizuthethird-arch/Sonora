import { z, type ZodType } from "zod";

// Every event carries these fields. Payloads are defined per event, next to the envelope.
const PLAIN_ID = /^[A-Za-z0-9._-]{1,64}$/;

export const eventEnvelopeFields = {
  id: z.uuid(),
  occurred_at: z.iso.datetime(),
  correlation_id: z.string().regex(PLAIN_ID),
};

export type EventSpec<Payload extends ZodType> = {
  readonly type: string;
  readonly version: number;
  readonly payload: Payload;
};

// Builds the schema for one event version: the shared envelope fields, the type and version fixed to the spec,
// and the payload parsed with its own schema. Unknown top-level fields are refused.
export function eventSchema<Payload extends ZodType>(spec: EventSpec<Payload>) {
  return z
    .object({
      ...eventEnvelopeFields,
      type: z.literal(spec.type),
      version: z.literal(spec.version),
      payload: spec.payload,
    })
    .strict();
}
