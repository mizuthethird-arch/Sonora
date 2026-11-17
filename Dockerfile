FROM node:24.22.3-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5 AS workspace
RUN corepack enable
WORKDIR /workspace
RUN chown node:node /workspace
USER node
COPY --chown=node:node package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY --chown=node:node apps/api/package.json apps/api/
COPY --chown=node:node packages/config/package.json packages/config/
COPY --chown=node:node modules/_template/package.json modules/_template/
COPY --chown=node:node infra/seed/package.json infra/seed/
RUN pnpm install --frozen-lockfile
COPY --chown=node:node . .
