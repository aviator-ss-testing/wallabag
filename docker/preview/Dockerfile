# Wallabag preview dependency-cache image for e2b sandboxes.
#
# This image is a DEPENDENCY CACHE, not the running app. Aviator's preview
# system git-clones the repo fresh into /code on every launch, which wipes
# anything baked into /code. So we stage installed deps + a seed DB under
# /opt/wallabag-deps (outside /code, so it survives the clone), and
# .aviator/scripts/preview-setup.sh copies them into the freshly-cloned
# workspace at runtime.
#
# Build via the e2b CLI:  bash docker/preview/build.sh e2b   (config: e2b.toml)
#
# Node 24 satisfies both the runbook branches (engines >=20) and upstream
# master (>=24), so a preview works regardless of which the sandbox checks out.

FROM php:8.2-bookworm

ARG DEBIAN_FRONTEND=noninteractive
ARG NODE_VERSION=24

# System packages + Node.js
RUN apt-get update \
    && apt-get install -y \
        ca-certificates curl gnupg lsb-release openssl software-properties-common \
        git git-lfs \
        libmcrypt-dev libicu-dev libpq-dev libxml2-dev libpng-dev libjpeg-dev \
        libwebp-dev libsqlite3-dev imagemagick libmagickwand-dev libtidy-dev \
        libonig-dev libzip-dev libfreetype6-dev zlib1g-dev \
        build-essential unzip \
        postgresql postgresql-client redis-server \
    && curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g yarn \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions wallabag needs. -j parallelizes the compile across cores.
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j "$(nproc)" \
        bcmath gd gettext iconv intl mbstring opcache \
        pdo pdo_mysql pdo_pgsql pdo_sqlite sockets tidy zip

RUN printf "no\nno\nno\n" | pecl install redis-6.1.0 \
    && printf "\n" | pecl install imagick-3.7.0 \
    && docker-php-ext-enable redis imagick

# Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Coding-agent tooling (claude CLI installs to /root/.local/bin — symlink it
# onto PATH so the agent can find it).
RUN curl -fsSL https://claude.ai/install.sh | bash -s 2.1.62 \
    && ln -sf /root/.local/bin/claude /usr/local/bin/claude \
    && git lfs install

# --- Dependency cache (survives the runtime clone into /code) ----------------
ENV DEPS_CACHE=/opt/wallabag-deps
WORKDIR ${DEPS_CACHE}

# Copy the full source (minus vendor/node_modules, which Dockerfile.dockerignore
# excludes). composer's autoload generation scans classmap entries like
# app/AppKernel.php, so the source must be present — a manifests-only copy fails.
COPY . ${DEPS_CACHE}/

# PHP deps. --no-scripts skips wallabag's post-install hooks (they need runtime
# app config); the autoloader is still generated, so vendor/autoload_runtime.php
# exists. NOT --optimize: a build-time optimized classmap would bake absolute
# paths; the runtime resolves classes relative to /code instead. Composer runs
# anonymously against GitHub (the repo's .composer-auth.json token is stale and
# makes auth *fail*; public packages download fine without it).
RUN COMPOSER_ALLOW_SUPERUSER=1 composer install \
        --no-interaction --no-progress --no-scripts --prefer-dist

# Node deps.
RUN yarn install --frozen-lockfile

# Seed sqlite DB so previews have schema + content immediately. Placed under
# the cache (not /code) so it survives the runtime clone; the setup script
# seeds /code/data/db/wallabag.sqlite from it.
RUN mkdir -p data/db \
    && cp docker/preview/seed.sqlite data/db/wallabag.sqlite \
    && chmod 666 data/db/wallabag.sqlite
