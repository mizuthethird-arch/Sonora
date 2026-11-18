# Secrets and environments

Staging and production are separate. Each has its own secrets, and one database user per module (identity, catalog, media, playback, library, search, recommender, realtime, notification, analytics, platform).

## What is built

- **Config at boot.** `packages/kernel` `loadConfig(schema, env)` parses the environment with zod and coerces numbers. `bootConfig` logs the missing or invalid keys (never their values) and exits with code 1. Required keys are defined by each app. The boot check requires `DATABASE_URL` and `RABBITMQ_URL` (RabbitMQ, as the event bus task T026 says).
- **Local secret store.** `createLocalSecretStore(directory)` reads a secret named like AWS (`sonora/<env>/db/<module>`) from a file of the same path. `moduleSecretName(env, module)` builds the names and refuses unknown environments and modules.
- **Local setup.** `scripts/secrets-local.sh init staging` (or `production`) writes one random password per module into `.secrets-local/`, which is gitignored. Existing values are kept.
- **Deploy materialisation.** `materializeSecrets({ store, environment, names, directory })` writes each secret to its own file with mode 0400 in an owner-only directory. A secret from another environment is refused before anything is written. A rotated secret replaces the old file on the next run.
- **`.env` guard.** `scripts/check-env-files.sh` rejects any tracked or staged env file except `.env.example`. It runs in the pre-commit hook and in CI.

## Decisions

- **Secrets backend.** The roadmap said SOPS with age. The stack says AWS Secrets Manager or SSM. For now there is a local mock with the same names and behaviour. The real AWS setup is a TODO below.
- **Hosting.** The Hostinger VPS, as the roadmap says. T016 (VPS) and T017 (production Compose) are not built yet.
- **Messaging.** `RABBITMQ_URL` is required, as the event bus task T026 says.
- **One user per module.** Kept from T013 and T025, even though the issue's stack note says one Prisma database.

## TODO (AWS, not built)

- Least-privilege IAM users per environment. Test that the staging key gets AccessDenied on a production bucket GetObject.
- Real AWS Secrets Manager or SSM store behind the `SecretStore` interface, with the same names.
- Staging containers cannot resolve production network hosts (needs the VPS network).
- Rotation drill on the real backend: `sops edit` replaced by the AWS rotation, redeploy, and the backend picks up the new value.
