export const ROLES = ["api", "worker", "media-worker", "realtime"] as const;

export type Role = (typeof ROLES)[number];

export type RoleProfile = {
  readonly http: boolean;
  readonly websockets: boolean;
  readonly outbox: boolean;
  readonly consumers: boolean;
  readonly jobs: boolean;
  readonly mediaJobs: boolean;
};

const OFF: RoleProfile = {
  http: false,
  websockets: false,
  outbox: false,
  consumers: false,
  jobs: false,
  mediaJobs: false,
};

const PROFILES: Readonly<Record<Role, RoleProfile>> = {
  api: { ...OFF, http: true },
  worker: { ...OFF, outbox: true, consumers: true, jobs: true },
  "media-worker": { ...OFF, mediaJobs: true },
  realtime: { ...OFF, websockets: true },
};

// Fails boot on an unknown or missing ROLE, so a typo never starts the wrong process.
export function parseRole(value: string | undefined): Role {
  const role = ROLES.find((candidate) => candidate === value);
  if (role === undefined) {
    const received = value === undefined ? "nothing" : `"${value}"`;
    throw new Error(`ROLE must be one of ${ROLES.join(", ")}; got ${received}`);
  }
  return role;
}

export function roleProfile(role: Role): RoleProfile {
  return PROFILES[role];
}
