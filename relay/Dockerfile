FROM node:22.11.0-bookworm-slim AS builder
WORKDIR /app

ENV NODE_ENV=development

COPY package.json package-lock.json* ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev


FROM node:22.11.0-bookworm-slim AS runtime
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV HOST=0.0.0.0

RUN groupadd --system --gid 10001 relay \
 && useradd  --system --uid 10001 --gid relay --home /app --shell /usr/sbin/nologin relay

COPY --from=builder --chown=relay:relay /app/node_modules ./node_modules
COPY --from=builder --chown=relay:relay /app/dist         ./dist
COPY --chown=relay:relay package.json ./

USER relay
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/v1/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"

CMD ["node", "dist/server.js"]
