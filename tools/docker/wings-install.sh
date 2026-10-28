#!/bin/sh
# Installs Wings on the A03 and registers it with the local Panel as node 1.
# Docker has no bridge on this kernel, so Wings uses Docker's host network:
# each server binds its allocation port directly on the phone.
set -e
VER=v1.13.4
P=/var/www/pterodactyl
art() { su -s /bin/sh nginx -c "php83 $P/artisan $*"; }

rc-update add docker default >/dev/null
curl -sLo /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/download/$VER/wings_linux_arm64
chmod 755 /usr/local/bin/wings

if ! mariadb -N panel -e 'select id from nodes where id=1' | grep -q 1; then
	art p:location:make --short=home --long=Phone
	LOC=$(mariadb -N panel -e "select id from locations where short='home'")
	art p:node:make --name=A03 --description=Phone --locationId=$LOC --fqdn=192.168.1.160 \
		--public=1 --scheme=http --proxy=0 --maintenance=0 --maxMemory=1700 --overallocateMemory=0 \
		--maxDisk=15000 --overallocateDisk=0 --uploadSize=100 --daemonListeningPort=8080 \
		--daemonSFTPPort=2022 --daemonBase=/var/lib/pterodactyl/volumes
fi
NODE=$(mariadb -N panel -e "select id from nodes where name='A03'")
for port in 25565 25566 25567 25568 25569 25570; do
	mariadb panel -e "insert into allocations (node_id, ip, ip_alias, port, created_at, updated_at)
		select $NODE, '0.0.0.0', '192.168.1.160', $port, now(), now() from dual
		where not exists (select 1 from allocations where node_id=$NODE and port=$port)"
done
echo "== node $NODE ok"

mkdir -p /etc/pterodactyl
if [ ! -f /etc/pterodactyl/config.yml ]; then
	art p:node:configuration $NODE > /etc/pterodactyl/config.yml
	cat >> /etc/pterodactyl/config.yml <<'YML'
docker:
  network:
    name: host
    driver: host
    network_mode: host
    interface: 127.0.0.1
    ispn: false
YML
	chmod 600 /etc/pterodactyl/config.yml
fi

cat > /etc/init.d/wings <<'SVC'
#!/sbin/openrc-run
description="Pterodactyl Wings"
command=/usr/local/bin/wings
command_background=true
pidfile=/run/wings.pid
output_log=/var/log/wings.out
error_log=/var/log/wings.out
depend() { need docker net; after nginx; }
SVC
chmod 755 /etc/init.d/wings
rc-update add wings default >/dev/null
rc-service wings restart
i=0; until wget -qO- http://127.0.0.1:8080/api/system 2>&1 | grep -q -i "unauth\|401\|error" || [ $i -ge 40 ]; do sleep 1; i=$((i+1)); done
tail -15 /var/log/wings.out | cut -c1-220
echo "== wings started"
