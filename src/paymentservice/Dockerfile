# Copyright 2020 Google LLC
# Licensed under the Apache License, Version 2.0

FROM node:20-alpine AS builder
RUN apk add --no-cache python3 make g++ gcc
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm ci --omit=dev

FROM node:20-alpine
WORKDIR /usr/src/app
COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY . .

EXPOSE 50051
ENTRYPOINT ["node", "index.js"]
