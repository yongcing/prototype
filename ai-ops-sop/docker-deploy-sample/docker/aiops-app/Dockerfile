# ── Stage 1: build aiops-contract/typescript ─────────────────────────────────
FROM node:20.18-alpine AS contract-builder
WORKDIR /build/aiops-contract/typescript
COPY aiops-contract/typescript/package*.json ./
RUN npm ci
COPY aiops-contract/typescript/ ./
RUN npm run build

# ── Stage 2: build aiops-app ──────────────────────────────────────────────────
FROM node:20.18-alpine AS app-builder
WORKDIR /build/aiops-app
# Copy contract dist so local dep resolves
COPY --from=contract-builder /build/aiops-contract/typescript /build/aiops-contract/typescript
COPY aiops-app/package*.json ./
RUN npm ci --legacy-peer-deps
COPY aiops-app/ ./
RUN npm run build

# ── Stage 3: runtime ──────────────────────────────────────────────────────────
FROM node:20.18-alpine AS runner
WORKDIR /usrapp

# Standalone server + static assets
COPY --from=app-builder /build/aiops-app/.next/standalone/ ./
COPY --from=app-builder /build/aiops-app/.next/static/ ./.next/static/
COPY --from=app-builder /build/aiops-app/public/ ./public/

# Log directory placeholder and run script
RUN mkdir -p /usrapp/log /usrapp/config

COPY deploy/docker/aiops-app/run.sh /usrapp/run.sh
RUN chmod +x /usrapp/run.sh

EXPOSE 8080
ENTRYPOINT ["/usrapp/run.sh"]
