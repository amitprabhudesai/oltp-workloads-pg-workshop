FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# postgresql-client from Ubuntu repos (14.x) works against PostgreSQL 16.
# All psql features used in the workshop exercises are available in 14+.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       postgresql-client \
       watch \
    && rm -rf /var/lib/apt/lists/*
