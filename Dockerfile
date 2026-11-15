ARG NODE_VERSION=24.22.3

FROM node:${NODE_VERSION}-alpine AS workspace
WORKDIR /workspace
RUN corepack enable
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
USER node
