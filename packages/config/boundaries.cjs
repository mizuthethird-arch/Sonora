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
      name: "no-circular-module-facades",
      severity: "error",
      comment:
        "Two module facades must not depend on each other, directly or through other facades. See docs/boundaries.md#no-circular-module-facades",
      from: { path: "^modules/[^/]+/src/public/" },
      to: { path: "^modules/[^/]+/src/public/", circular: true },
    },
    {
      name: "no-database-client-outside-infrastructure",
      severity: "error",
      comment:
        "Database clients are imported only inside modules/<name>/src/infrastructure, so a module owns its data. apps/api/src/database holds the current Prisma setup until the schema moves into modules. See docs/boundaries.md#no-database-client-outside-infrastructure",
      from: { pathNot: ["^modules/[^/]+/src/infrastructure/", "^apps/api/src/database/"] },
      to: { path: "(^|/node_modules/)(@prisma/client|@prisma/adapter-mariadb|mysql2?|mariadb|knex|drizzle-orm)(/|$)" },
    },
  ],
  options: {
    doNotFollow: { path: "node_modules" },
    exclude: { path: "(^|/)(node_modules|dist|generated|fixtures)/" },
    tsPreCompilationDeps: true,
    enhancedResolveOptions: {
      exportsFields: ["exports"],
      conditionNames: ["import", "require", "node", "default"],
      extensions: [".ts", ".js", ".json"],
    },
  },
};
