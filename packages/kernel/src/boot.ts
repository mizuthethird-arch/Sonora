import { parseRole, type Role } from "./role.js";

export type BootDeps = {
  readonly start: (role: Role) => Promise<void>;
  readonly exit: (code: number) => void;
  readonly log: (message: string) => void;
};

const EXIT_CODE_INVALID_CONFIGURATION = 1;

// A bad ROLE stops the process before anything starts, with a message that names what is allowed.
export async function bootRole(environment: Record<string, string | undefined>, deps: BootDeps): Promise<void> {
  let role: Role;
  try {
    role = parseRole(environment["ROLE"]);
  } catch (error) {
    deps.log(error instanceof Error ? error.message : "ROLE is invalid");
    deps.exit(EXIT_CODE_INVALID_CONFIGURATION);
    return;
  }
  await deps.start(role);
}
