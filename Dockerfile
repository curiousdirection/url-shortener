# check=skip=InvalidDefaultArgInFrom
# Built by infra/scripts/release.sh, which passes NODE_VERSION from .node-version.
ARG NODE_VERSION

FROM node:${NODE_VERSION}-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:${NODE_VERSION}-slim
ENV NODE_ENV=production
WORKDIR /app

# Lets the app verify the RDS server certificate (sslmode=verify-full in DATABASE_URL). The
# build fails if AWS changes the bundle: set the checksum to `sha256sum` of a fresh download.
ADD --checksum=sha256:90a6f1a7978a1b1b096dca6c57511ca48d3b8cf052f8e704baf358f34ea2f21b --chown=node:node https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /usr/local/share/rds-ca-bundle.pem
ENV NODE_EXTRA_CA_CERTS=/usr/local/share/rds-ca-bundle.pem

COPY package.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY migrations ./migrations

USER node
# `exec` makes node the main process, so it gets SIGTERM directly.
CMD ["sh", "-c", "node dist/migrate.js && exec node dist/server.js"]
