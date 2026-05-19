# Copyright 2020 Google LLC
# Licensed under the Apache License, Version 2.0

FROM eclipse-temurin:21-jdk AS builder
WORKDIR /app

COPY ["build.gradle", "gradlew", "settings.gradle", "./"]
COPY gradle gradle
RUN chmod +x gradlew

# Download dependencies first (cached layer)
RUN ./gradlew downloadRepos

COPY . .
RUN chmod +x gradlew
RUN ./gradlew installDist -PskipTests

FROM eclipse-temurin:21-jre
WORKDIR /app

COPY --from=builder /app/build/install/hipstershop/ /app/

EXPOSE 9555
ENTRYPOINT ["/app/bin/AdService"]
