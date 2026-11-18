import js from "@eslint/js";
import { defineConfig } from "eslint/config";
import tseslint from "typescript-eslint";

export default defineConfig(
  { ignores: ["**/node_modules/**", "**/dist/**", "**/generated/**", "fixtures/**"] },
  js.configs.recommended,
  tseslint.configs.recommendedTypeChecked,
  { languageOptions: { parserOptions: { projectService: true } } },
  { files: ["**/*.{js,cjs,mjs}"], extends: [tseslint.configs.disableTypeChecked] },
);
