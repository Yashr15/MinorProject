# Copyright 2020 Google LLC
# Licensed under the Apache License, Version 2.0

FROM golang:1.25-alpine AS builder
RUN apk add --no-cache ca-certificates git

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -o /checkoutservice .

FROM alpine AS release
RUN apk add --no-cache ca-certificates
WORKDIR /src
COPY --from=builder /checkoutservice ./server

EXPOSE 5050
ENTRYPOINT ["/src/server"]
