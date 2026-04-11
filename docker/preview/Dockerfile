# Wallabag Preview Environment Docker image for e2b sandboxes.
#
# Design notes:
# - Single-stage build so caches match between build-time and runtime.
# - .git is shipped with the image (via Dockerfile.dockerignore) so runtime
#   git fetch is an incremental delta, not a full clone.
# - SQLite seed DB with ~13 articles baked in so the app has content.
# - Uses Symfony's built-in dev server (`bin/console server:run`) — same
#   as local development. No nginx, no php-fpm, no user permission
#   issues. Toolbar is disabled via app/config/config_dev.yml.

FROM php:8.2-fpm-bookworm

ARG DEBIAN_FRONTEND=noninteractive
ARG NODE_VERSION=20

# System packages + Node.js
RUN apt-get update && apt-get install -y \
      ca-certificates curl gnupg lsb-release git git-lfs openssl \
      redis-server \
    && curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get update && apt-get install -y \
      libicu-dev libpq-dev libxml2-dev libpng-dev libjpeg-dev libwebp-dev \
      libsqlite3-dev libmagickwand-dev libtidy-dev libonig-dev libzip-dev \
      libfreetype6-dev zlib1g-dev libxslt1-dev \
      nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions wallabag needs. -j parallelizes across CPU cores
# (otherwise each extension compiles single-threaded and this step takes 5-10min).
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j "$(nproc)" \
      pdo_sqlite pdo_pgsql pdo_mysql mbstring intl gd exif opcache \
      pcntl tidy xsl zip bcmath

# Sockets — required by php-amqplib. Separate RUN so the big gd/intl compile above stays cached.
RUN docker-php-ext-install -j "$(nproc)" sockets

# Redis extension
RUN pecl install redis && docker-php-ext-enable redis

# Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Yarn
RUN npm install -g yarn

# Dev tools required by the coding sandbox (claude CLI, etc.)
RUN curl -fsSL https://claude.ai/install.sh | bash -s 2.1.62
# claude installs to /root/.local/bin which isn't in the default PATH.
# Symlink to /usr/local/bin so the coding agent can find it.
RUN ln -sf /root/.local/bin/claude /usr/local/bin/claude
RUN bash -l -c "git lfs install"
RUN npm install -g npm@latest

WORKDIR /code

# Copy full wallabag source including .git (Dockerfile.dockerignore allows .git)
COPY . /code/

# Record the SHA the image was built from so runtime can diff against it to
# detect what actually changed on the branch (and skip composer/yarn when
# nothing relevant changed).
RUN git -C /code rev-parse HEAD > /code/.preview-image-sha

# Install PHP dependencies (including dev deps — we run in --env=dev at runtime).
RUN composer install --no-interaction --prefer-dist --optimize-autoloader

# Install Node deps and build frontend
RUN yarn install --frozen-lockfile && yarn build:dev

# Copy the seed sqlite DB into the data dir
RUN mkdir -p /code/data/db \
    && cp /code/docker/preview/seed.sqlite /code/data/db/wallabag.sqlite \
    && chmod 666 /code/data/db/wallabag.sqlite

# Required directories for runtime logs
RUN mkdir -p /var/log/app

EXPOSE 8000
