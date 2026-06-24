# ── Stage 1: Build the React/Vite SPA ────────────────────────────────────────
FROM node:22-alpine AS builder
WORKDIR /app

# VITE_API_URL=""  → all /api/* requests are relative (proxied by Nginx at runtime)
ARG VITE_API_URL=""
ENV VITE_API_URL=$VITE_API_URL

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# ── Stage 2: Serve with Nginx ─────────────────────────────────────────────────
FROM nginx:1.27-alpine

COPY --from=builder /app/dist /usr/share/nginx/html

# Place config as a template; the nginx Docker entrypoint runs envsubst on it
# at container start, writing the result to /etc/nginx/conf.d/default.conf.
# ${GATEWAY_URL} is substituted; $uri / $http_host are nginx vars — not touched.
COPY nginx.conf /etc/nginx/templates/default.conf.template

EXPOSE 3000

# Override at runtime: -e GATEWAY_URL=http://gateway.businessconnect.local:4000
ENV GATEWAY_URL=http://localhost:4000

CMD ["nginx", "-g", "daemon off;"]
