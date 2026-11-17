# Module boundaries

The repository is a modular monolith. The rules below are checked by dependency-cruiser on every pull request, before the tests. A failing check prints the rule name, and each name below is a link target.

Run the check locally:

```bash
docker compose run --rm workspace pnpm run check:boundaries
```

The rules live in `packages/config/boundaries.cjs`. Type-only imports count like any other import, so a type import cannot get around a rule. `packages/contracts` is a package, so every module, app and package may import its types.

## no-module-internals

A module imports another module only through `modules/<name>/src/public`.

**Bad**

```ts
// modules/catalog/src/service.ts
import { readPlaybackRows } from "../../playback/src/infrastructure/repository.js";
```

**Good**

```ts
// modules/catalog/src/service.ts
import type { PlaybackFacade } from "../../playback/src/public/index.js";
```

## no-app-past-public-entry

An app imports only `modules/<name>/module.ts` and `modules/<name>/src/public`.

**Bad**

```ts
// apps/api/src/routes.ts
import { loadCatalog } from "../../../modules/catalog/src/domain/catalog.js";
```

**Good**

```ts
// apps/api/src/routes.ts
import { registerCatalog } from "../../../modules/catalog/module.js";
```

## no-package-imports-module-or-app

Packages never import modules or apps. Dependencies point from apps to modules to packages.

**Bad**

```ts
// packages/kernel/src/index.ts
import type { CatalogFacade } from "../../../modules/catalog/src/public/index.js";
```

**Good**

```ts
// modules/catalog/src/public/index.ts
import type { TrackId } from "../../../../packages/contracts/src/index.js";
```

## no-module-imports-app

A module never imports an app. Dependencies point from apps to modules to packages.

**Bad**

```ts
// modules/catalog/src/service.ts
import { routes } from "../../../apps/api/src/routes.js";
```

**Good**

```ts
// apps/api/src/routes.ts
import { registerCatalog } from "../../../modules/catalog/module.js";
```

## no-circular-module-facades

Modules must not depend on each other in a cycle, directly or through their internals. Share the type through `packages/contracts` or publish an event instead.

**Bad**

```ts
// modules/catalog/src/service.ts imports modules/playback/src/public
// modules/playback/src/service.ts imports modules/catalog/src/public
```

**Good**

```ts
// modules/playback/src/public/index.ts
import type { TrackId } from "../../../../packages/contracts/src/index.js";
```

## no-database-client-outside-infrastructure

Database clients (`@prisma/client`, `@prisma/adapter-mariadb`, `mysql`, `mysql2`, `mariadb`, `knex`, `drizzle-orm`) are imported only inside `modules/<name>/src/infrastructure`, so a module owns its data. The generated Prisma client (`generated/prisma`) counts as a database client. `apps/api/src/database` is a temporary exception: it holds the current Prisma setup until the schema moves into modules.

**Bad**

```ts
// modules/catalog/src/service.ts
import mysql from "mysql2";
```

**Good**

```ts
// modules/catalog/src/infrastructure/repository.ts
import mysql from "mysql2";
```

## public-entry-exports

Not a dependency-cruiser rule: `packages/config/src/architecture.test.ts` runs one test per folder in `modules/`. The public entry `modules/<name>/src/public/index.ts` exports only the facade, its types and its event schemas. A value export must be named `<Something>EventSchema`. `export *` and default exports are not allowed.

**Bad**

```ts
export function helper(): void {}
export * from "./internal.js";
```

**Good**

```ts
export type { CatalogFacade } from "./facade.js";
export { TrackAddedEventSchema } from "./events.js";
```

## Limits

- `node_modules` is not followed, but imports that resolve into it are still checked, so a database client cannot hide there.
- CI has no generated Prisma client (`generated/` is ignored), so there the import is matched by its path text. Locally the generated files are scanned too.
- A module importing a file outside `apps`, `modules` and `packages` (for example `scripts/`) is not checked yet.
- Only static imports are checked. A dynamic `import(name)` or `require(name)` with a variable cannot be resolved, so do not use it to reach another module.
- The root `typescript` 6.0.3 exists only because dependency-cruiser needs a TypeScript with a JavaScript API, which TypeScript 7 does not ship. Do not bump it to 7 at the root.
