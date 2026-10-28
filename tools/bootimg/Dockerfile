# Tools for unpacking, inspecting and repacking Samsung boot/vbmeta images
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
        mkbootimg lz4 xxd file python3 tar cpio gzip openssl android-sdk-libsparse-utils fdisk \
    && rm -rf /var/lib/apt/lists/*
COPY avbtool.py /usr/local/bin/avbtool
RUN chmod +x /usr/local/bin/avbtool
WORKDIR /work
