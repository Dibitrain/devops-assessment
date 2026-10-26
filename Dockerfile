# syntax=docker/dockerfile:1.7

# ---- Build stage: full toolchain, compiles TypeScript, then strips dev dependencies ----------------
FROM node:22-trixie-slim AS build
WORKDIR /app

# Dependency layer first so it is cached until package*.json changes. --ignore-scripts blocks
# install-time scripts from third-party packages (supply-chain hardening); none are needed here.
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts

COPY tsconfig.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

# ---- Runtime stage: distroless = no shell, no package manager, minimal CVE surface ---------------
# Same Debian 13 base as the build stage, so any native modules stay ABI-compatible.
FROM gcr.io/distroless/nodejs22-debian13:nonroot AS runtime
WORKDIR /app

ENV NODE_ENV=production \
    PORT=3000 \
    METRICS_PORT=9100

COPY --from=build /app/package.json ./package.json
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

# UID 65532. Files stay root-owned and read-only to the process, which suits readOnlyRootFilesystem.
USER nonroot
EXPOSE 3000 9100

# The distroless entrypoint is node itself. Node runs as PID 1 and handles SIGTERM explicitly
# (see src/server.ts), so no init shim (tini) is needed for graceful shutdown.
CMD ["dist/server.js"]
