# Copyright 2020 Google LLC
# Licensed under the Apache License, Version 2.0

FROM python:3.12-slim AS base

FROM base AS builder
RUN apt-get -qq update \
    && apt-get install -y --no-install-recommends \
        g++ \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --prefix="/install" -r requirements.txt

FROM base
WORKDIR /recommendation_server
COPY --from=builder /install /usr/local
COPY . .

EXPOSE 8080
ENTRYPOINT ["python", "recommendation_server.py"]
