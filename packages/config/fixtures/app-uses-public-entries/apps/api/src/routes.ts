import { registerCatalog } from "../../../modules/catalog/module.js";
import type { CatalogFacade } from "../../../modules/catalog/src/public/index.js";

export const register = registerCatalog;
export type Facade = CatalogFacade;
