# ── Stage 1: Build ───────────────────────────────────────────────────────────
FROM swift:6.1-jammy AS builder
WORKDIR /build

# Resolve dependencies first (layer cached until Package files change)
COPY Package.swift Package.resolved ./
RUN swift package resolve

# Copy sources and resources, then compile
COPY Sources Sources
COPY Resources Resources
RUN swift build -c release --product SimingServer

# ── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM ubuntu:22.04

# Swift runtime dependencies for Ubuntu 22.04
RUN apt-get update && apt-get install -y \
        libatomic1 \
        libcurl4 \
        libxml2 \
        libc6 \
        tzdata \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Swift runtime libraries (compiler toolchain excluded)
COPY --from=builder /usr/lib/swift/linux /usr/lib/swift/linux

# Application binary
COPY --from=builder /build/.build/release/SimingServer /app/SimingServer

# Migrations — applied at startup by MigrationRunner
COPY migrations /app/migrations

WORKDIR /app
EXPOSE 8080

# MIGRATIONS_PATH defaults to "migrations" relative to CWD (/app/migrations).
# Override DATABASE_URL or PG* env vars at runtime.
ENV MIGRATIONS_PATH=/app/migrations

CMD ["./SimingServer"]
