FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# Install PostgreSQL 16 client tools (psql, pgbench, pg_dump, etc.)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       curl \
       gnupg2 \
       lsb-release \
       watch \
    && install -d /usr/share/postgresql-common/pgdg \
    && curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail \
       https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
       https://apt.postgresql.org/pub/repos/apt \$(lsb_release -cs)-pgdg main" \
       > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       postgresql-client-16 \
    && rm -rf /var/lib/apt/lists/*
