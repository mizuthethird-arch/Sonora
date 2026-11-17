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
