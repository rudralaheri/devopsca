# Stage 1: Build (install prod dependencies)
FROM node:22-alpine AS build
RUN apk update && apk upgrade
WORKDIR /app
COPY package.json package-lock.json* ./
# We don't have a package-lock yet, so use npm install if ci fails, or just npm install --omit=dev
RUN npm install --omit=dev

# Stage 2: Runtime (minimal image)
FROM node:22-alpine AS runtime
RUN apk update && apk upgrade
WORKDIR /app

# Create a non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy dependencies and source code from build stage
COPY --from=build /app/node_modules ./node_modules
COPY package.json ./
COPY src/ ./src/

# Change ownership to non-root user
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

EXPOSE 3000

# Healthcheck hitting the health endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["npm", "start"]
