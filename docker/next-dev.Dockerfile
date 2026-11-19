# tfh-local generic Next.js `next dev` image (admin panel, funnels). Build context = the app's apps/ checkout.
# No production build (keeps memory/CPU sane). Config comes ONLY from docker-compose.yml environment.
FROM node:20
WORKDIR /app
COPY package.json package-lock.json .npmrc* ./
RUN npm ci --no-audit --no-fund
COPY . .
# Drop the repo's committed env files (they point at remote develop/stage/prod hosts, Sentry, etc.).
RUN rm -f .env .env.* && rm -rf .git
ENV NEXT_TELEMETRY_DISABLED=1 PORT=3000
EXPOSE 3000
CMD ["npx", "next", "dev", "-H", "0.0.0.0", "-p", "3000"]
