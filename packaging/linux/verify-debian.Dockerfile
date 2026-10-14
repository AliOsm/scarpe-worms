FROM debian:12-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 libcrypt1 libstdc++6 libgcc-s1 libx11-6 libx11-xcb1 libxcursor1 \
    libxi6 libxrandr2 libxcb1 libxkbcommon0 libxkbcommon-x11-0 \
    libwayland-client0 libwayland-cursor0 xvfb xauth desktop-file-utils \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /tmp
