#!/bin/bash
set -euo pipefail

echo "Starting Postgres..."
pg_ctlcluster 15 main start || service postgresql start

echo "Starting Redis..."
redis-server --daemonize yes

echo "Setting up Postgres user and database..."
su - postgres -c "psql -c \"CREATE USER wallabag WITH PASSWORD 'wallapass';\"" 2>/dev/null || true
su - postgres -c "psql -c \"CREATE DATABASE wallabag OWNER wallabag;\"" 2>/dev/null || true

echo "Writing wallabag config..."
cat > app/config/parameters.yml << PARAMS
parameters:
    database_driver: pdo_pgsql
    database_host: 127.0.0.1
    database_port: 5432
    database_name: wallabag
    database_user: wallabag
    database_password: wallapass
    database_path: null
    database_table_prefix: wallabag_
    database_socket: null
    database_charset: utf8
    domain_name: ${PREVIEW_URL:-https://localhost}
    server_name: wallabag
    mailer_dsn: null://null
    locale: en
    secret: preview-secret-change-me
    twofactor_auth: false
    twofactor_sender: no-reply@wallabag.org
    fosuser_registration: true
    fosuser_confirmation: false
    fos_oauth_server_access_token_lifetime: 3600
    fos_oauth_server_refresh_token_lifetime: 1209600
    from_email: no-reply@wallabag.org
    rss_limit: 50
    rabbitmq_host: localhost
    rabbitmq_port: 5672
    rabbitmq_user: guest
    rabbitmq_password: guest
    rabbitmq_prefetch_count: 10
    redis_scheme: tcp
    redis_host: localhost
    redis_port: 6379
    redis_path: null
    redis_password: null
PARAMS

echo "Copying cached dependencies..."
if [ -d /opt/wallabag-deps/vendor ]; then
    cp -rn /opt/wallabag-deps/vendor ./vendor 2>/dev/null || true
fi
if [ -d /opt/wallabag-deps/node_modules ]; then
    cp -rn /opt/wallabag-deps/node_modules ./node_modules 2>/dev/null || true
fi

echo "Running composer install (using cache)..."
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-interaction --no-progress

echo "Running database migrations..."
php bin/console doctrine:migrations:migrate --no-interaction --env=dev

echo "Creating default admin user..."
php bin/console fos:user:create --super-admin admin admin@wallabag.org preview --env=dev 2>/dev/null || true

echo "Building frontend assets..."
yarn build:dev

echo "Starting wallabag dev server on port 443..."
nohup php bin/console server:run 0.0.0.0:443 --env=dev > /tmp/wallabag-server.log 2>&1 &

echo "Preview server started. Login with admin / preview"
