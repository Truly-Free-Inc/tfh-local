# tfh-local memberportal image: `next dev` (no production build; keeps memory sane).
# Build context = apps/memberportal.
FROM node:20
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
# `next build` (LOCAL_APP_MODE=prod) needs sharp's native binary for this platform (image blur placeholders).
# npm ci sometimes skips sharp's platform optional deps (npm/cli#4828); install them if sharp does not load.
RUN if [ -d node_modules/sharp ] && ! node -e "require('sharp')" 2>/dev/null; then \
      npm install --no-save --no-audit --no-fund "sharp@$(node -p "require('./node_modules/sharp/package.json').version")" \
      && node -e "require('sharp')"; fi
COPY . .
# Drop the repo's committed env files (they point at remote develop/stage/prod hosts). All config comes from
# docker-compose.yml environment, which points ONLY at local services.
RUN rm -f .env .env.* && rm -rf .git
ENV NEXT_TELEMETRY_DISABLED=1 PORT=3000
EXPOSE 3000
CMD ["npx", "next", "dev", "-H", "0.0.0.0", "-p", "3000"]
