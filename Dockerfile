FROM rust:1-trixie AS build
WORKDIR /build
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY web ./web
RUN cargo build --locked --release

FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 station && useradd --uid 10001 --gid station --no-create-home station \
    && install -d -o station -g station -m 0700 /data /quarantine
COPY --from=build /build/target/release/station-blanche /usr/local/bin/station-blanche
USER 10001:10001
ENV SB_LISTEN=0.0.0.0:8080
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 CMD curl --fail --silent http://127.0.0.1:8080/health/live || exit 1
ENTRYPOINT ["/usr/local/bin/station-blanche"]
