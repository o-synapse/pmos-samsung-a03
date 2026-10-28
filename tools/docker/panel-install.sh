#!/bin/sh
# Installs Pterodactyl Panel on the A03 (postmarketOS/Alpine, run as root).
# Panel at http://<phone>/ , MariaDB + Redis on localhost only.
# PANEL_AUTHOR (optional) is the email put on eggs you export.
set -e
VER=v1.15.2
DIR=/var/www/pterodactyl

apk add -q php83 php83-fpm php83-bcmath php83-ctype php83-curl php83-dom php83-fileinfo \
	php83-gd php83-iconv php83-intl php83-mbstring php83-openssl php83-pdo php83-pdo_mysql \
	php83-phar php83-posix php83-session php83-simplexml php83-sodium php83-tokenizer \
	php83-xml php83-xmlreader php83-xmlwriter php83-zip php83-pcntl php83-opcache \
	composer mariadb mariadb-client redis nginx curl tar openssl
echo "== packages ok"

# MariaDB: localhost only
if [ ! -d /var/lib/mysql/mysql ]; then
	mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql --skip-test-db >/dev/null
fi
sed -i 's/^skip-networking/#skip-networking/' /etc/my.cnf.d/mariadb-server.cnf
grep -q '^bind-address' /etc/my.cnf.d/mariadb-server.cnf || \
	sed -i 's/^\[mysqld\]/[mysqld]\nbind-address=127.0.0.1/' /etc/my.cnf.d/mariadb-server.cnf
sed -i 's/^bind .*/bind 127.0.0.1 -::1/' /etc/redis.conf
# Redis won't start on this arm64 4.14 kernel (fork COW bug) unless told to. It only
# holds cache/sessions/queue here, so turn off persistence: no background save, no fork.
grep -q '^ignore-warnings ARM64-COW-BUG' /etc/redis.conf || \
	printf '\nsave ""\nappendonly no\nignore-warnings ARM64-COW-BUG\n' >> /etc/redis.conf
for s in mariadb redis php-fpm83 nginx; do rc-update add $s default >/dev/null; done
rc-service mariadb start; rc-service redis restart

DBPASS_FILE=/root/.pterodactyl-db
[ -f $DBPASS_FILE ] || { umask 077; openssl rand -hex 24 > $DBPASS_FILE; }
DBPASS=$(cat $DBPASS_FILE)
mariadb -u root <<SQL
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DBPASS';
ALTER USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DBPASS';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
echo "== database ok"

mkdir -p $DIR && cd $DIR
if [ ! -f artisan ]; then
	curl -sLo panel.tar.gz https://github.com/pterodactyl/panel/releases/download/$VER/panel.tar.gz
	tar -xzf panel.tar.gz && rm panel.tar.gz
	chmod -R 755 storage/* bootstrap/cache/
fi
[ -f .env ] || cp .env.example .env
COMPOSER_ALLOW_SUPERUSER=1 php83 /usr/bin/composer.phar install --no-dev --optimize-autoloader --no-interaction -q
grep -q '^APP_KEY=base64' .env || php83 artisan key:generate --force
php83 artisan p:environment:setup --no-interaction --author="${PANEL_AUTHOR:-admin@example.com}" \
	--url=http://192.168.1.160 --timezone=UTC --cache=redis --session=redis --queue=redis \
	--redis-host=127.0.0.1 --redis-pass= --redis-port=6379 --settings-ui=true --telemetry=false
php83 artisan p:environment:database --no-interaction --host=127.0.0.1 --port=3306 \
	--database=panel --username=pterodactyl --password="$DBPASS"
php83 artisan migrate --seed --force
chown -R nginx:nginx $DIR
echo "== panel ok"

# php-fpm as nginx on a socket
sed -i 's/^user = .*/user = nginx/; s/^group = .*/group = nginx/; s#^listen = .*#listen = /run/php-fpm83.sock#;
	s/^;listen.owner = .*/listen.owner = nginx/; s/^;listen.group = .*/listen.group = nginx/' /etc/php83/php-fpm.d/www.conf

cat > /etc/nginx/http.d/pterodactyl.conf <<'NGX'
server {
    listen 80 default_server;
    server_name _;
    root /var/www/pterodactyl/public;
    index index.php;
    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php-fpm83.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGX
rm -f /etc/nginx/http.d/default.conf

# queue worker + scheduler
cat > /etc/init.d/pteroq <<'SVC'
#!/sbin/openrc-run
description="Pterodactyl queue worker"
command=/usr/bin/php83
command_args="/var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3"
command_user=nginx
command_background=true
pidfile=/run/pteroq.pid
depend() { need redis mariadb; }
SVC
chmod 755 /etc/init.d/pteroq
rc-update add pteroq default >/dev/null
echo '* * * * * php83 /var/www/pterodactyl/artisan schedule:run >/dev/null 2>&1' > /etc/crontabs/nginx
rc-update add crond default >/dev/null 2>&1 || true

rc-service php-fpm83 restart; rc-service nginx restart; rc-service pteroq restart; rc-service crond restart || true
echo "== services ok"
