# syntax=docker/dockerfile:1

# =============================================================================
# Frontend Next.js 16 — build multi-stage (deps -> builder -> runner)
# =============================================================================
ARG NODE_VERSION=20

# ---------- Etapa 1: dependencias ----------
# Solo depende de package*.json: mientras no cambien, Docker reutiliza esta
# capa (y su `npm ci`) aunque cambie todo el código fuente.
FROM node:${NODE_VERSION}-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci

# ---------- Etapa 2: build ----------
FROM node:${NODE_VERSION}-alpine AS builder
WORKDIR /app

# Las variables NEXT_PUBLIC_* se "queman" en el JavaScript durante `next build`,
# por eso se reciben como ARG de build y no como variables de runtime.
# (La llave publicable de Stripe es pública por diseño; no es un secreto.)
ARG NEXT_PUBLIC_API_BASE_URL=http://localhost:8000/api
ARG NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=
ENV NEXT_PUBLIC_API_BASE_URL=${NEXT_PUBLIC_API_BASE_URL} \
    NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=${NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY} \
    NEXT_TELEMETRY_DISABLED=1

COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# ---------- Etapa 3: runtime ----------
# Solo lo necesario para ejecutar el servidor: sin código fuente, sin
# devDependencies, sin cache de build.
FROM node:${NODE_VERSION}-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

# Usuario sin privilegios
RUN addgroup -S -g 1001 nodejs && adduser -S -u 1001 -G nodejs nextjs

COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000

# `node server.js` es el equivalente optimizado de `next start` para standalone.
CMD ["node", "server.js"]
