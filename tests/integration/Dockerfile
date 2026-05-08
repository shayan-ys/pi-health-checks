FROM debian:bookworm-slim
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash coreutils cron curl iproute2 procps util-linux \
      ca-certificates grep sed gawk && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /repo
