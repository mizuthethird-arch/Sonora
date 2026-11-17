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

## no-circular-module-facades

Two module facades must not depend on each other, directly or through other facades. Share the type through `packages/contracts` or publish an event instead.

**Bad**

```ts
// modules/catalog/src/public/index.ts imports PlaybackFacade
// modules/playback/src/public/index.ts imports CatalogFacade
```

**Good**

```ts
// modules/playback/src/public/index.ts
import type { TrackId } from "../../../../packages/contracts/src/index.js";
```

## no-database-client-outside-infrastructure

Database clients (`@prisma/client`, `@prisma/adapter-mariadb`, `mysql`, `mysql2`, `mariadb`, `knex`, `drizzle-orm`) are imported only inside `modules/<name>/src/infrastructure`, so a module owns its data. `apps/api/src/database` is a temporary exception: it holds the current Prisma setup until the schema moves into modules.

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
