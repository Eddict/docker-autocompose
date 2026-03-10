FROM node:22-alpine3.20
RUN npm install -g decomposerize@latest --omit=dev --no-audit --no-fund && npm cache clean --force
USER node
ENTRYPOINT ["decomposerize"]
CMD ["--help"]
