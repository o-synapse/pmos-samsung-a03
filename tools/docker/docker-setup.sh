#!/bin/sh
# Sets up Docker on the A03 (run as root, with crun-a03 next to this script).
# runc can't run on 4.14, and there is no bridge/iptables, so Docker gets crun
# through the crun-a03 wrapper and no default network (containers use host).
set -e
apk add -q docker jq crun
install -m 755 "$(dirname "$0")/crun-a03" /usr/local/bin/crun-a03
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{"bridge":"none","iptables":false,"ip6tables":false,"storage-driver":"overlay2","default-runtime":"crun-a03","runtimes":{"crun-a03":{"path":"/usr/local/bin/crun-a03"}}}
JSON
rc-update add docker default >/dev/null
rc-service docker restart
i=0; until docker info >/dev/null 2>&1 || [ $i -ge 30 ]; do sleep 1; i=$((i+1)); done
docker run --rm --network host alpine echo docker-ok
