// Dependabot fixes the capital "Bump" in its titles, so skip linting for that header format.
const dependabotBumpHeader = /^chore\((deps|deps-dev)\): Bump \S/;

export default {
  extends: ["@commitlint/config-conventional"],
  ignores: [(message) => dependabotBumpHeader.test(message)],
};
