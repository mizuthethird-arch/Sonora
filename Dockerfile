FROM node:26.13.1-alpine@sha256:6bd9ab43c0ec0190ca7b2d193906cb8b7edf6e7f4afa43ddeccd6452710bffb5 AS workspace
RUN corepack enable
WORKDIR /workspace
RUN chown node:node /workspace
USER node
COPY --chown=node:node package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY --chown=node:node apps/api/package.json apps/api/
COPY --chown=node:node packages/config/package.json packages/config/
COPY --chown=node:node packages/kernel/package.json packages/kernel/
COPY --chown=node:node packages/contracts/package.json packages/contracts/
COPY --chown=node:node modules/_template/package.json modules/_template/
COPY --chown=node:node infra/seed/package.json infra/seed/
RUN pnpm install --frozen-lockfile
COPY --chown=node:node . .
# Packages resolve to their built output at runtime; typecheck reads their source (customConditions).
RUN pnpm --filter @sonora/kernel --filter @sonora/contracts run build

FROM workspace AS build
RUN DATABASE_URL=mysql://build@localhost:3306/build pnpm --filter @sonora/api run build
RUN pnpm --filter @sonora/api deploy --prod /tmp/api-deploy

FROM node:26.13.1-alpine@sha256:6bd9ab43c0ec0190ca7b2d193906cb8b7edf6e7f4afa43ddeccd6452710bffb5 AS api
USER root
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
WORKDIR /app
COPY --from=build --chown=node:node /tmp/api-deploy/node_modules ./node_modules
COPY --from=build --chown=node:node /tmp/api-deploy/dist ./dist
COPY --from=build --chown=node:node /tmp/api-deploy/package.json ./package.json
ENV NODE_ENV=production
USER node
EXPOSE 3000
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:3000/health
CMD ["node", "dist/index.js"]
