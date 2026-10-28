# Build environment for the Samsung SM-A035F 4.14 kernel (AOSP clang r383902 is mounted from a volume)
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential bc bison flex libssl-dev libelf-dev python3 python-is-python3 \
        binutils-aarch64-linux-gnu device-tree-compiler cpio kmod perl rsync \
        curl ca-certificates libtinfo5 libncurses5 xz-utils git file \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /k/src
