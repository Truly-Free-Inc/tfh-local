# tfh-local memberportal image: `next dev` (no production build; keeps memory sane).
# Build context = apps/memberportal.
FROM node:20
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
# Drop the repo's committed env files (they point at remote develop/stage/prod hosts). All config comes from
# docker-compose.yml environment, which points ONLY at local services.
RUN rm -f .env .env.* && rm -rf .git
ENV NEXT_TELEMETRY_DISABLED=1 PORT=3000
EXPOSE 3000
CMD ["npx", "next", "dev", "-H", "0.0.0.0", "-p", "3000"]
