FROM node:24-alpine AS base
WORKDIR /app
COPY package*.json ./

FROM base AS dependencies
RUN npm ci

FROM dependencies AS build
COPY . .
RUN npm run build

FROM base AS production-dependencies
RUN npm ci --omit=dev

# node:24-bookworm-slim is choosen because of ffmpgeg dependencies
FROM node:24-bookworm-slim AS production
WORKDIR /app

# Dev dependencies are required, because of tsc.
COPY --from=build /app/dist ./dist

COPY --from=production-dependencies /app/node_modules ./node_modules
COPY --from=build /app/src/ffmpeg-7.0.2-amd64-static ./src/ffmpeg-7.0.2-amd64-static
COPY package.json ./

RUN chmod +x src/ffmpeg-7.0.2-amd64-static/*

ENV NODE_ENV=production

EXPOSE 3000

CMD ["node", "dist/index.js"]