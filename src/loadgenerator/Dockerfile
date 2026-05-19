# Copyright 2020 Google LLC
# Licensed under the Apache License, Version 2.0

FROM python:3.12-slim AS builder
RUN apt-get -qq update \
    && apt-get install -y --no-install-recommends \
        g++ \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --prefix="/install" -r requirements.txt

FROM python:3.12-slim
WORKDIR /loadgen
COPY --from=builder /install /usr/local
COPY . .

# Locust is the load testing framework
ENTRYPOINT ["locust", "--host=http://${FRONTEND_ADDR}", "--headless", "-u", "${USERS:-10}"]
