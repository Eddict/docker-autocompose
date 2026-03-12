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

# Copy the entire decomposerize repo (including Makefile and packages)
COPY decomposerize/ ./decomposerize/

# Set working directory to the root of the decomposerize repo
WORKDIR /build/decomposerize

# Install dependencies
RUN yarn install --frozen-lockfile --non-interactive \
  && yarn cache clean

# Build using the repository Makefile (Makefile is now present)
RUN make build

# Install the CLI package globally (install from the package folder)
# Adjust path if the CLI package lives elsewhere in the workspace
RUN npm install -g ./packages/decomposerize \
  && yarn cache clean \
  && npm cache clean --force

# Final stage: runtime image without Node build tools
FROM python:3.13-alpine3.21
ARG POETRY_VERSION
LABEL org.opencontainers.image.source=https://github.com/Eddict/docker-autocompose

# Install Poetry and runtime dependencies (including Node for decomposerize CLI)
RUN apk add --no-cache python3 py3-pip nodejs \
  && python3 -m pip install --no-cache-dir poetry${POETRY_VERSION:+==${POETRY_VERSION}}

COPY --from=build /usr/local/lib/node_modules/decomposerize /usr/local/lib/node_modules/decomposerize
# Create symlink for CLI entrypoint so __dirname resolves correctly
RUN ln -s /usr/local/lib/node_modules/decomposerize/cli.js /usr/local/bin/decomposerize

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
