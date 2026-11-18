// Dependabot fixes the capital "Bump" in its titles, so skip linting for a bare one-line title in that format.
// Only the title is skipped: a message with a body or footer is still linted.
const dependabotBumpHeader = /^chore\((deps|deps-dev)\): Bump \S[^\n]*\n?$/;

export default {
  extends: ["@commitlint/config-conventional"],
  ignores: [(message) => dependabotBumpHeader.test(message)],
};
