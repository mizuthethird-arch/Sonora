# Route registry

`apps/api` is the single HTTP entry. Each module registers its routes with a prefix and a permission. `packages/kernel` builds the route table and mounts it.

## Registering a route

A module lists its routes in `httpRoutes` on its `defineModule` call:

```ts
httpRoutes: [
  { method: "get", path: "/genres", permission: "public", handler },
  { method: "post", path: "/tracks", permission: "catalog:track:write", handler },
],
```

- The full path is the module's `routePrefix` plus `path`. A path of `/` is the prefix itself.
- `permission` is `public` or a name such as `catalog:track:read`. A route without one fails boot.
- A path must start with `/`.

Boot fails when two modules register the same method and full path, and the error names both modules. Nothing is mounted in that case.

## What the edge does

In this order, for every request:

1. Client-supplied `X-Internal-*`, `X-Principal-*`, `X-User-Id` and `X-Profile-Id` headers are removed.
2. CORS allows the configured `WEB_ORIGIN` only. Without it, no origin is allowed.
3. Rate limits per IP: a general limit for every route, and a stricter limit under `/auth`. A limited request gets 429 with `Retry-After`. The numbers are proposals in `DEFAULT_RATE_LIMITS`.
4. The route registry.

`GET /api/v1/openapi.json` serves the merged contract document, except when `NODE_ENV` is `production`.

## Configuration

- `WEB_ORIGIN`: the one origin allowed to call the API from a browser.
- `TRUST_PROXY_HOPS` (0 to 5): how many reverse proxies sit in front of the API. Behind Traefik, set it to 1, so per-IP limits see the client and not the proxy.
- `REDIS_URL`: where the per-IP rate-limit counters are kept. Without it, they stay in memory for this process. Each limiter (general and auth) has its own Redis prefix.
- `NODE_ENV`: `production` turns off the OpenAPI document.

## Not built yet

- **Session check.** The permission on a route is not enforced yet. Sessions come from identity (T039 to T041).
- **Per-session rate limits.** Only per-IP limits exist.
- **Composition endpoints.** `composeSections` in `packages/kernel` loads page sections in parallel, with a timeout per section. Home and page endpoints wait for module facades (T048 onwards).

## Later: a remote route (P16)

A route that moves to an extracted service keeps its registration here. The change is in the route's target, not in its path, so callers do not change:

1. Mark the route `remote` with the base URL of the new service. The registry proxies the request there.
2. The proxy forwards the same permission and a `RequestContext`, signed with an internal token. The signing is T141 and is not built.
3. The module's facade tests run again against the HTTP client of the new service (T030, T142).

Until step 1, a route stays local and the registry is unchanged.
