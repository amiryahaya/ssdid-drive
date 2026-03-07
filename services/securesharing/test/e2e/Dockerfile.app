# Phoenix Application for E2E Tests
FROM elixir:1.18-alpine

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    npm \
    curl \
    postgresql-client

WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files
COPY mix.exs mix.lock ./
COPY config config

# Install dependencies
ENV MIX_ENV=dev
RUN mix deps.get && mix deps.compile

# Copy application code
COPY lib lib
COPY priv priv

# Compile the application
RUN mix compile

# Create entrypoint script
RUN echo '#!/bin/sh' > /entrypoint.sh && \
    echo 'set -e' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Wait for database' >> /entrypoint.sh && \
    echo 'echo "Waiting for database..."' >> /entrypoint.sh && \
    echo 'until pg_isready -h postgres -U securesharing; do' >> /entrypoint.sh && \
    echo '  sleep 1' >> /entrypoint.sh && \
    echo 'done' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Setup database' >> /entrypoint.sh && \
    echo 'echo "Setting up database..."' >> /entrypoint.sh && \
    echo 'mix ecto.create' >> /entrypoint.sh && \
    echo 'mix ecto.migrate' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Seed admin user' >> /entrypoint.sh && \
    echo 'echo "Seeding admin user..."' >> /entrypoint.sh && \
    echo 'mix run priv/repo/seeds/e2e_admin_seed.exs' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Start server' >> /entrypoint.sh && \
    echo 'echo "Starting Phoenix server..."' >> /entrypoint.sh && \
    echo 'exec mix phx.server' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

EXPOSE 4000

CMD ["/entrypoint.sh"]
