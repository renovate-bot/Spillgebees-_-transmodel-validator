FROM node:26-slim@sha256:e6bedef217677b276c591795e169840edd9096dbf13f29df8ef8d1856b8820bc AS base

# node 25+ no longer bundles corepack; it reads the pnpm version from packageManager in package.json
# renovate: datasource=npm depName=corepack
ARG COREPACK_VERSION=0.36.0
RUN npm install --global corepack@${COREPACK_VERSION} && corepack enable

FROM base AS deps

WORKDIR /app

COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY packages/core/package.json packages/core/package.json
COPY packages/cli/package.json packages/cli/package.json
COPY packages/web/package.json packages/web/package.json

RUN pnpm install --frozen-lockfile

FROM base AS build

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/packages/core/node_modules ./packages/core/node_modules
COPY --from=deps /app/packages/cli/node_modules ./packages/cli/node_modules
COPY --from=deps /app/packages/web/node_modules ./packages/web/node_modules
COPY . .

# Build core first (cli + web depend on it), then cli + web
RUN pnpm --filter @transmodel-validator/core build && \
    pnpm --filter @transmodel-validator/cli build && \
    pnpm --filter @transmodel-validator/web build

FROM node:26-slim@sha256:e6bedef217677b276c591795e169840edd9096dbf13f29df8ef8d1856b8820bc AS runtime

# Run as non-root user for security
RUN adduser --disabled-password --gecos "" appuser

WORKDIR /app

# Nitro produces a standalone server — only the .output directory is needed
COPY --from=build /app/packages/web/.output ./packages/web/.output

# Schema cache directory (owned by appuser)
RUN mkdir -p /home/appuser/.cache/transmodel-validator/schemas && \
    chown -R appuser:appuser /home/appuser/.cache

USER appuser

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000

EXPOSE 3000

CMD ["node", "packages/web/.output/server/index.mjs"]
