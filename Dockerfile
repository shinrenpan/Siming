# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM swift:6.2 AS builder
WORKDIR /build
COPY . .
RUN swift build -c release --product SimingServer

# ── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM ubuntu:24.04
RUN apt-get update \
    && apt-get install -y --no-install-recommends libssl3 libcurl4t64 curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /usr/lib/swift/linux/ /usr/lib/swift/linux/
RUN echo "/usr/lib/swift/linux" >> /etc/ld.so.conf && ldconfig
COPY --from=builder /build/.build/release/SimingServer ./SimingServer
COPY migrations/  ./migrations/
COPY packages/    ./packages/
COPY config.yml   ./config.yml
EXPOSE 8080
ENTRYPOINT ["./SimingServer"]
