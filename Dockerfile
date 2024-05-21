
FROM node:18.17-alpine AS mainDeps
WORKDIR /app

ARG name
ARG proxy

RUN [ -z "$proxy" ] || sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories
RUN apk add --no-cache libc6-compat && npm install -g pnpm@8.6.0
# if proxy exists, set proxy
RUN [ -z "$proxy" ] || pnpm config set registry https://registry.npmmirror.com

COPY pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ./packages ./packages
COPY ./projects/$name/package.json ./projects/$name/package.json

RUN [ -f pnpm-lock.yaml ] || (echo "Lockfile not found." && exit 1)

RUN pnpm i

FROM node:18.17-alpine AS builder
WORKDIR /app

ARG name
ARG proxy

COPY package.json pnpm-workspace.yaml .npmrc ./
COPY --from=mainDeps /app/node_modules ./node_modules
COPY --from=mainDeps /app/packages ./packages
COPY ./projects/$name ./projects/$name
COPY --from=mainDeps /app/projects/$name/node_modules ./projects/$name/node_modules

RUN [ -z "$proxy" ] || sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories

RUN apk add --no-cache libc6-compat && npm install -g pnpm@8.6.0

ENV NODE_OPTIONS="--max-old-space-size=4096"
RUN pnpm --filter=$name build

FROM node:18.17-alpine AS runner
WORKDIR /app

ARG name
ARG proxy

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

RUN [ -z "$proxy" ] || sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories
RUN apk add --no-cache curl ca-certificates \
  && update-ca-certificates

COPY --from=builder /app/projects/$name/public /app/projects/$name/public
COPY --from=builder /app/projects/$name/next.config.js /app/projects/$name/next.config.js
COPY --from=builder --chown=nextjs:nodejs /app/projects/$name/.next/standalone /app/
COPY --from=builder --chown=nextjs:nodejs /app/projects/$name/.next/static /app/projects/$name/.next/static
COPY --from=builder --chown=nextjs:nodejs /app/projects/$name/.next/server/chunks /app/projects/$name/.next/server/chunks
COPY --from=builder --chown=nextjs:nodejs /app/projects/$name/.next/server/worker /app/projects/$name/.next/server/worker

COPY --from=mainDeps /app/node_modules/tiktoken ./node_modules/tiktoken
RUN rm -rf ./node_modules/tiktoken/encoders

COPY --from=builder /app/projects/$name/package.json ./package.json 
COPY ./projects/$name/data /app/data

RUN chown -R nextjs:nodejs /app/data

ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1
ENV PORT=3000

EXPOSE 3000

USER nextjs

ENV serverPath=./projects/$name/server.js

ENTRYPOINT ["sh","-c","node --max-old-space-size=4096 ${serverPath}"]
