# Build stage: build decomposerize from source
ARG YARN_VERSION=1.22.19
FROM node:22-alpine3.21 AS build
WORKDIR /build

# Install system build tools needed for `make build`
RUN apk add --no-cache make build-base python3 git openssh-client

# Enable corepack and prepare yarn
RUN corepack enable \
  && corepack prepare yarn@${YARN_VERSION} --activate
  # && corepack prepare yarn@stable --activate

# # Copy entire decomposerize workspace so Yarn sees all manifests
# COPY decomposerize/ .
# Copy manifests first to leverage Docker cache for dependencies
COPY decomposerize/package.json decomposerize/yarn.lock ./decomposerize/
# If you want even better caching, copy workspace package.json files explicitly:
# COPY decomposerize/packages/decomposerize/package.json decomposerize/packages/decomposerize/package.json
# (add other workspace package.json paths as needed)

WORKDIR /build/decomposerize

# right before RUN yarn install --immutable
# RUN echo "=== files in /build ===" && ls -la \
#   && echo "=== package.json ===" && cat package.json \
#   && echo "=== yarn.lock head ===" && head -n 40 yarn.lock

# Install deps (Yarn v3+ prefers --immutable)
# RUN yarn install --immutable
# Install deps (Yarn v1 uses --frozen-lockfile)
RUN yarn install --frozen-lockfile --non-interactive \
  && yarn cache clean
# # Build using the repository Makefile, then install globally
# RUN make build \
#   && npm install -g . \
#   && npm cache clean --force

# Copy the rest of the decomposerize repo
WORKDIR /build
COPY decomposerize/ ./decomposerize/

# Build the project from the repo root as per contributing instructions
WORKDIR /build/decomposerize


# Build using the repository Makefile
RUN make build \
  && echo '=== DEBUG: dist contents after build ===' \
  && ls -la ./packages/decomposerize/dist || echo 'dist directory missing'

# Install the CLI package globally (install from the package folder)
# Adjust path if the CLI package lives elsewhere in the workspace
RUN npm install -g ./packages/decomposerize \
  && yarn cache clean \
  && npm cache clean --force

# Final stage: runtime image without Node build tools
ARG POETRY_VERSION=
FROM python:3.13-alpine3.21
LABEL org.opencontainers.image.source=https://github.com/Eddict/docker-autocompose

# Install Poetry and runtime dependencies (including Node for decomposerize CLI)
RUN apk add --no-cache python3 py3-pip nodejs \
  && python3 -m pip install --no-cache-dir poetry${POETRY_VERSION:+==${POETRY_VERSION}} \
  && poetry --version
  # && python3 -m pip install --no-cache-dir "poetry==1.8.1"

# Copy decomposerize runtime files and binary from build stage
COPY --from=build /usr/local/lib/node_modules/decomposerize /usr/local/lib/node_modules/decomposerize
COPY --from=build /usr/local/bin/decomposerize /usr/local/bin/decomposerize

# Optional smoke test to ensure CLI works
RUN /usr/local/bin/decomposerize --version

WORKDIR /usr/src/app

# Copy Python project files
COPY poetry.lock pyproject.toml README.md ./
COPY src ./src

# Install Python dependencies
RUN poetry install --no-interaction --no-ansi

COPY docker/combined/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/sh"]
