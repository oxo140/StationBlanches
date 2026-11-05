FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      clamav-daemon clamav-freshclam clamav ca-certificates netcat-openbsd \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -o clamav -g clamav -m 0755 /var/lib/clamav /run/clamav
COPY deploy/clamav/clamd.conf /etc/clamav/clamd.conf
COPY deploy/clamav/freshclam.conf /etc/clamav/freshclam.conf
COPY --chmod=755 deploy/clamav/entrypoint.sh /usr/local/bin/start-clamav
USER clamav
EXPOSE 3310
HEALTHCHECK --interval=30s --timeout=5s --start-period=15m --retries=3 CMD printf 'zPING\0' | nc -w 3 127.0.0.1 3310 | grep -q PONG
ENTRYPOINT ["/usr/local/bin/start-clamav"]
