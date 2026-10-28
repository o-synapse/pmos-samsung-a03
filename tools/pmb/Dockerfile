# pmbootstrap 3.12.1 for building the SM-A035F postmarketOS image (run with --privileged; work dir is the a03-pmb volume)
FROM alpine:3.22
RUN apk add --no-cache git python3 openssl sudo util-linux losetup coreutils multipath-tools android-tools \
    && git clone --depth 1 -b 3.12.1 https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git /opt/pmbootstrap \
    && ln -s /opt/pmbootstrap/pmbootstrap.py /usr/local/bin/pmbootstrap \
    && adduser -D -u 1000 pmos && echo 'pmos ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/pmos
COPY patches/mkinitfs-retry.py /tmp/
RUN python3 /tmp/mkinitfs-retry.py && grep -q run_mkinitfs /opt/pmbootstrap/pmb/install/_install.py
USER pmos
WORKDIR /home/pmos
