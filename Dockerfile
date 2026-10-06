FROM node:22-slim@sha256:c3de60bf2f9dd0ac6370e6117950ff62d6e339527e7472301c9c78a017978392 AS deps

RUN corepack enable && corepack prepare pnpm@10.28.2 --activate

WORKDIR /app

COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY packages/core/package.json packages/core/package.json
COPY packages/cli/package.json packages/cli/package.json
COPY packages/web/package.json packages/web/package.json

RUN pnpm install --frozen-lockfile

FROM node:22-slim@sha256:c3de60bf2f9dd0ac6370e6117950ff62d6e339527e7472301c9c78a017978392 AS build

RUN corepack enable && corepack prepare pnpm@10.28.2 --activate

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

FROM node:22-slim@sha256:c3de60bf2f9dd0ac6370e6117950ff62d6e339527e7472301c9c78a017978392 AS runtime

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
