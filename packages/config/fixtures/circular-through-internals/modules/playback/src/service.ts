import type { CatalogFacade } from "../../catalog/src/public/index.js";

export const catalogName = "catalog" as const;
export type Dependency = CatalogFacade;
