# ---- Build Stage ----
FROM elixir:1.15.8-alpine AS builder

# Set build environment
ENV MIX_ENV=prod
ENV LC_ALL=en_US.UTF-8

# Install build dependencies
RUN apk add --no-cache build-base git tzdata

# Prepare build dir
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy dependencies first for caching
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy the rest of the application
COPY config config
COPY lib lib
COPY priv priv
COPY assets assets

# Compile and release
RUN mix compile --warnings-as-errors
RUN mix release

# ---- Release Stage ----
FROM alpine:3.20.3

RUN apk add --no-cache libstdc++ ncurses-libs openssl tzdata bash curl

WORKDIR /app

# Run as non-root user
RUN adduser -D -h /app appuser
USER appuser

# Copy release from builder
COPY --from=builder --chown=appuser:appuser /app/_build/prod/rel/dunda ./

# Set environment variables
ENV HOME=/app
ENV MIX_ENV=prod

EXPOSE 4000

CMD ["bin/dunda", "start"]
