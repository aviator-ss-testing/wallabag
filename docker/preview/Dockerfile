# Wallabag preview image for e2b sandboxes.
#
# Bakes the repo + installed deps + built frontend + a seed DB directly into
# /code. The Aviator preview launch finds an existing matching repo in /code and
# takes a git FETCH fast-path (not a fresh clone); its working-tree cleanup is
# `git reset --hard` + `git clean -fd` (no -x), which RESPECTS .gitignore. Since
# vendor/, node_modules/, web/build/*, and data/db/wallabag*.sqlite are all
# gitignored, the baked artifacts survive the launch untouched — a preview starts
# with everything already in place, so no copy/symlink/install is needed.
#
# Build via the e2b CLI:  bash docker/preview/build.sh e2b   (config: e2b.toml)
# Node 24 covers both the runbook branches (engines >=20) and master (>=24).

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

# Coding-agent tooling (claude installs to /root/.local/bin — symlink onto PATH).
RUN curl -fsSL https://claude.ai/install.sh | bash -s 2.1.62 \
    && ln -sf /root/.local/bin/claude /usr/local/bin/claude \
    && git lfs install

# --- Bake repo + deps + frontend build + seed DB into /code -----------------
# Clone the actual (public) preview repo so /code's origin matches at runtime
# and the launch fetch fast-path triggers. --filter=blob:none (matching the
# runtime's own clone) keeps it lean while preserving the full-branch refspec
# (+refs/heads/*:refs/remotes/origin/*) — a shallow/--single-branch clone would
# only track master, so the runtime's `git fetch origin <runbook-branch>` would
# never create origin/<branch> and `git switch` would fail with "invalid reference".
RUN git clone --filter=blob:none \
        https://github.com/aviator-ss-testing/wallabag.git /code
WORKDIR /code

# PHP deps. --no-scripts skips wallabag's post-install hooks (they need runtime
# config); the autoloader (incl. vendor/autoload_runtime.php) is still generated.
RUN COMPOSER_ALLOW_SUPERUSER=1 composer install \
        --no-interaction --no-progress --no-scripts --prefer-dist

# Node deps + frontend build. Output lands in web/build/, which is gitignored
# (/web/build/* in .gitignore) and therefore survives the launch clean.
RUN yarn install --frozen-lockfile
RUN yarn build:dev

# Seed sqlite DB (gitignored -> survives). The build context supplies the file.
COPY docker/preview/seed.sqlite data/db/wallabag.sqlite
RUN chmod 666 data/db/wallabag.sqlite

# Record the baked commit OUTSIDE /code — a file inside /code would be deleted by
# the launch `git clean -fd`. preview-setup.sh diffs the runbook branch against
# this to decide whether anything actually needs reinstalling/rebuilding.
RUN git -C /code rev-parse HEAD > /preview-image-sha
