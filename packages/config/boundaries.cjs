const DATABASE_CLIENTS = [
  "@prisma/client",
  "@prisma/adapter-mariadb",
  "mysql",
  "mysql2",
  "mariadb",
  "knex",
  "drizzle-orm",
  "pg",
  "better-sqlite3",
  "mongodb",
  "typeorm",
  "sequelize",
  "kysely",
  "@libsql/client",
].join("|");

// A bare specifier that could not be resolved, a path inside node_modules, or the generated Prisma client.
const DATABASE_CLIENT_PATH = `^(${DATABASE_CLIENTS})(/|$)|(^|/)node_modules/(${DATABASE_CLIENTS})(/|$)|(^|/)generated/prisma(/|$)`;

/** @type {import("dependency-cruiser").IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: "no-module-internals",
      severity: "error",
      comment:
        "A module may import another module only through modules/<name>/src/public. See docs/boundaries.md#no-module-internals",
      from: { path: "^modules/([^/]+)/" },
      to: {
        path: "^modules/[^/]+/",
        pathNot: ["^modules/$1/", "^modules/[^/]+/src/public/"],
      },
    },
    {
      name: "no-app-past-public-entry",
      severity: "error",
      comment:
        "An app may import only modules/<name>/module.ts and modules/<name>/src/public. See docs/boundaries.md#no-app-past-public-entry",
      from: { path: "^apps/" },
      to: {
        path: "^modules/",
        pathNot: ["^modules/[^/]+/module\\.ts$", "^modules/[^/]+/src/public/"],
      },
    },
    {
      name: "no-package-imports-module-or-app",
      severity: "error",
      comment: "Packages never import modules or apps. See docs/boundaries.md#no-package-imports-module-or-app",
      from: { path: "^packages/" },
      to: { path: "^(modules|apps)/" },
    },
    {
      name: "no-module-imports-app",
      severity: "error",
      comment: "A module never imports an app. See docs/boundaries.md#no-module-imports-app",
      from: { path: "^modules/" },
      to: { path: "^apps/" },
    },
    {
      name: "no-circular-module-facades",
      severity: "error",
      comment:
        "Modules must not depend on each other in a cycle, directly or through their internals. See docs/boundaries.md#no-circular-module-facades",
      from: { path: "^modules/([^/]+)/" },
      to: { path: "^modules/[^/]+/src/public/", pathNot: "^modules/$1/", circular: true },
    },
    {
      name: "no-database-client-outside-infrastructure",
      severity: "error",
      comment:
        "Database clients are imported only inside modules/<name>/src/infrastructure, so a module owns its data. apps/api/src/database holds the current Prisma setup until the schema moves into modules. See docs/boundaries.md#no-database-client-outside-infrastructure",
      from: { pathNot: ["^modules/[^/]+/src/infrastructure/", "^apps/api/src/database/", "^apps/api/src/generated/"] },
      to: { path: DATABASE_CLIENT_PATH },
    },
  ],
  options: {
    doNotFollow: { path: "node_modules" },
    exclude: { path: "^packages/config/fixtures/|^apps/[^/]+/dist/" },
    tsPreCompilationDeps: true,
    enhancedResolveOptions: {
      exportsFields: ["exports"],
      conditionNames: ["import", "require", "node", "default"],
    },
  },
};
