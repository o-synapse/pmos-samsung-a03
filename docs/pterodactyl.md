# Docker + Pterodactyl on the A03

The phone hosts game servers (Minecraft) with the [Pterodactyl](https://pterodactyl.io) Panel
(web UI) and Wings (the daemon that runs servers in Docker containers), all on the phone itself.

- Panel: `http://192.168.1.160`
- Wings API: port 8080, SFTP: port 2022
- Game ports: **25565–25570** (six allocations on node `A03`)

## Limits — read this first

The Samsung 4.14 kernel can't have the container features Docker normally uses (enabling them
breaks the Wi-Fi driver; see [quirks.md](quirks.md#kernel-samsung-414)). As a result:

- **No container isolation for PIDs/IPC:** containers see the host's processes.
- **No network isolation:** every container uses the host network. Two servers can't share a
  port; each one needs its own allocation.
- **No device cgroup:** device access isn't restricted.
- **Memory limits work, CPU limits don't.** One busy server can take all four cores.
- **RAM:** 3 GB in total, ~1.7 GB is given to Wings. Realistically one small Paper server
  (1–1.5 GB heap, a handful of players). There's no swap.

**Only run images and server jars you trust** — a container here is close to running it on the
host.

## 1. Docker

From the Mac, copy the scripts to the phone and run the setup as root:

```bash
scp tools/docker/crun-a03 tools/docker/docker-setup.sh tools/docker/panel-install.sh tools/docker/wings-install.sh user@192.168.1.160:/tmp/
```

```bash
ssh -t user@192.168.1.160 'sudo sh /tmp/docker-setup.sh'
```

`docker-setup.sh` installs `docker jq crun`, installs the `crun-a03` wrapper to
`/usr/local/bin`, writes `/etc/docker/daemon.json`:

```json
{"bridge":"none","iptables":false,"ip6tables":false,"storage-driver":"overlay2",
 "default-runtime":"crun-a03","runtimes":{"crun-a03":{"path":"/usr/local/bin/crun-a03"}}}
```

and enables Docker at boot. It ends with `docker-ok` if a test container ran.

**Why the wrapper:** runc 1.5 needs `/proc/thread-self` (missing on 4.14), so crun is used.
`crun-a03` edits each container's OCI spec before handing it to crun: it removes the PID and
IPC namespaces, the mqueue mount, the device rules and the pids/blockIO/cpu limits — all
things this kernel doesn't have.

## 2. Panel

```bash
ssh -t user@192.168.1.160 'sudo sh /tmp/panel-install.sh'
```

Installs PHP 8.3, MariaDB, Redis and nginx, then Pterodactyl Panel v1.15.2 in
`/var/www/pterodactyl`. Notable choices:

- MariaDB and Redis listen on localhost only. The database password is generated and kept in
  `/root/.pterodactyl-db`.
- Redis runs with `ignore-warnings ARM64-COW-BUG` and no persistence (it refuses to start on
  this kernel otherwise; with no persistence it never forks, which is when the bug would
  matter). It only holds cache, sessions and the queue.
- `composer` is run with `php83` explicitly (Alpine's default PHP lacks the extensions).
- Services: `mariadb`, `redis`, `php-fpm83`, `nginx`, `pteroq` (queue worker), and a cron job
  for the scheduler.

## 3. Wings

```bash
ssh -t user@192.168.1.160 'sudo sh /tmp/wings-install.sh'
```

Downloads Wings v1.13.4 (arm64), creates location `home` and node `A03` (FQDN `192.168.1.160`,
1700 MB memory, 15 GB disk), adds allocations 25565–25570, writes
`/etc/pterodactyl/config.yml` with Docker's **host** network, and installs the `wings`
OpenRC service.

## 4. Admin account

Create it yourself (it asks for email, username, name and password interactively):

```bash
ssh -t user@192.168.1.160 'sudo php83 /var/www/pterodactyl/artisan p:user:make'
```

Answer **yes** to "Is this user an administrator?". Then log in at `http://192.168.1.160`.

## 5. A Minecraft server

In the Panel: Admin → Servers → Create New.

- Node `A03`, allocation `192.168.1.160:25565` (or another free port from the list).
- Nest **Minecraft**, egg **Paper**.
- Memory about **1200 MB**, disk a few GB, CPU limit doesn't matter (not enforced).
- Docker image: one of the Java images the egg offers (Java 21 for current Minecraft).

The first start downloads the image and the Paper jar and takes a few minutes. Players connect
to `192.168.1.160:25565`. To play from outside your home network you'd forward that port on
your router.

Turn view-distance and simulation-distance down (e.g. 6/4 in `server.properties`) — with
four slow cores and no GPU the phone is the bottleneck.

## Troubleshooting

| Symptom | Check |
|---|---|
| Panel shows node offline (red heart) | `sudo rc-service wings status`, `tail /var/log/wings.out` |
| Server won't start, "address in use" | Another server already uses that port — host networking |
| Container fails with `clone: EINVAL`, `bpf`, `mqueue` | Docker isn't using the wrapper: check `docker info \| grep -i runtime` shows `crun-a03` |
| Panel 500 errors | `tail /var/www/pterodactyl/storage/logs/laravel-*.log`; is `redis` running? |
| Phone very slow / OOM | Lower the server's memory; there's no swap and only ~2.7 GB usable RAM |
