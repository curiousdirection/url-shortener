# check=skip=InvalidDefaultArgInFrom
# Built by infra/scripts/release.sh, which passes NODE_VERSION from .node-version.
ARG NODE_VERSION

FROM node:${NODE_VERSION}-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:${NODE_VERSION}-slim
ENV NODE_ENV=production
WORKDIR /app

# Lets the app verify the RDS server certificate (PGSSLMODE=verify-full).
ADD --chown=node:node https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /usr/local/share/rds-ca-bundle.pem
ENV NODE_EXTRA_CA_CERTS=/usr/local/share/rds-ca-bundle.pem

COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist
COPY migrations ./migrations

USER node
# `exec` makes node the main process, so it gets SIGTERM directly.
CMD ["sh", "-c", "node dist/migrate.js && exec node dist/server.js"]
