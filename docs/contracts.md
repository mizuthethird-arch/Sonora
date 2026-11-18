# Contracts

`packages/contracts` holds the zod schemas for HTTP routes and events, the merged OpenAPI document, and the typed client that the web app uses. Every response and event is parsed with its schema on both sides.

## What is in the package today

- `src/event-envelope.ts`: `eventSchema(spec)` builds an event schema from the envelope fields `id` (UUID), `type`, `version`, `occurred_at` (ISO 8601 UTC), `correlation_id`, and a `payload` parsed by its own schema. Top-level extra fields are refused.
- `src/routes/`: route groups. Each group names the module that owns its routes, or `kernel`. Today the only group is `kernel`, for `GET /health/live` and `GET /health/ready`.
- `src/openapi/`: OpenAPI 3.1 per group and merged, generated with `@asteasolutions/zod-to-openapi`.
- `src/client/`: a typed client that checks the status and the body of every response.
- `src/compat/` and `src/cli/`: the compatibility rules and the checker run in CI.
- `openapi.json` and `contract.json`: the committed merged document and the contract version. The document must match what the code generates.

Modules have no routes, facades or events yet. When a module adds one, it is added to its route group, its facade types and its event schema here, and the document is regenerated.

## Additive-first rule

A change to a contract is additive first:

- Adding an optional field, a new route, a new event, or a new enum value that consumers can ignore is allowed in any version.
- Removing a field, removing a route or a response status, or narrowing an enum (removing a value) is breaking.
- A breaking change needs both: a version bump in `contract.json`, and an overlap period in `overlapUntil` (an ISO date until which the old shape keeps working). Then both sides can ship.

`scripts/contracts-check.sh <base-ref>` runs in every pull request. It fails when:

- `openapi.json` is not what the code generates;
- a change is breaking without a version bump, or without a noted overlap period.

`oasdiff` lists every change for the reviewer, but the gate is the rule above. oasdiff v1.39.0 is pinned by digest in the script.

The baseline is the pull request's base branch (`dev` in this repository), not `main`. `main` only changes through promotion, so it lags behind.

## Event versioning

- An event keeps its `type`. The `version` in the envelope is an integer and starts at 1.
- A breaking change to an event's payload is a new version, `vN+1`, with its own schema. Producers publish both versions during the overlap period, and consumers move to the new one before the old one is removed.
- A consumer rejects an envelope whose version it does not know, and does not guess.

## Regenerating the snapshot

After changing any route group, run from the repository root:

```bash
docker compose -f docker-compose.yml run --rm --no-deps -T workspace sh -c \
  "cd packages/contracts && pnpm run --silent build >/dev/null && node dist/cli/emit.js /dev/stdout" > packages/contracts/openapi.json
```

Then run `scripts/contracts-check.sh origin/dev` to check it against the base branch.

## Not yet covered

- Event schemas for real events (for example `play.recorded`) are added with the module that publishes them.
- The web client is not yet wired into `apps/web`, which does not exist yet.
- The check does not compare event schemas, only HTTP routes.
