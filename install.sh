#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 /path/to/project 1|2"
    echo "1 = MySQL, 2 = SQLite"
    exit 1
fi

PROJECT_SRC=$(realpath "$1")
DB_TYPE="$2"

PROJECT_NAME=$(basename "$PROJECT_SRC")
TARGET_DIR="/var/www/$PROJECT_NAME"
NGINX_CONF="/etc/nginx/sites-available/$PROJECT_NAME"
CERT_DIR="/etc/ssl/$PROJECT_NAME"

apt update -y
apt install -y php php-fpm php-cli

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

apt install -y nginx openssl

# выбор БД
if [ "$DB_TYPE" = "1" ]; then
    apt install -y mysql-server php-mysql
    echo "MySql installed"
elif [ "$DB_TYPE" = "2" ]; then
    apt install -y php-sqlite3
    echo "[+] Sqlite installed"
else
    echo "database not supported. mysql and sqlite only supported"
    exit 1
fi

rm -rf "$TARGET_DIR"
cp -r "$PROJECT_SRC" "$TARGET_DIR"
chown -R www-data:www-data "$TARGET_DIR"

mkdir -p "$CERT_DIR"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$CERT_DIR/key.key" \
    -out "$CERT_DIR/cert.crt" \
    -subj "/CN=$PROJECT_NAME"

cat > "$NGINX_CONF" <<EOF
server {
    listen 443 ssl;
    server_name localhost;

    ssl_certificate     $CERT_DIR/cert.crt;
    ssl_certificate_key $CERT_DIR/key.key;

    root $TARGET_DIR;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$PHP_VERSION-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}

server {
    listen 80;
    server_name localhost;
    return 301 https://\$host\$request_uri;
}
EOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

systemctl enable nginx php$PHP_VERSION-fpm
systemctl restart nginx php$PHP_VERSION-fpm

if [ "$DB_TYPE" = "1" ]; then
    systemctl enable mysql
    systemctl restart mysql
fi
