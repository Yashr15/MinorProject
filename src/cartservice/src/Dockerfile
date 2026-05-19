# Copyright 2020 Google LLC
# Licensed under the Apache License, Version 2.0

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS builder
WORKDIR /app

COPY cartservice.csproj .
RUN dotnet restore cartservice.csproj -r linux-x64

COPY . .
RUN dotnet publish cartservice.csproj \
    -p:PublishSingleFile=true \
    -r linux-x64 \
    --self-contained true \
    -p:PublishTrimmed=true \
    -p:TrimMode=full \
    -c Release \
    -o /cartservice

FROM mcr.microsoft.com/dotnet/runtime-deps:10.0-noble-chiseled
WORKDIR /app
COPY --from=builder /cartservice .

EXPOSE 7070
ENV DOTNET_EnableDiagnostics=0
ENTRYPOINT ["/app/cartservice"]
