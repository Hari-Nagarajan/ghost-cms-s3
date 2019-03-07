# https://docs.ghost.org/supported-node-versions/
# https://github.com/nodejs/LTS
FROM node:8-alpine

# grab su-exec for easy step-down from root
RUN apk add --no-cache 'su-exec>=0.2'

RUN apk add --no-cache \
# add "bash" for "[["
		bash

ENV NODE_ENV production

ENV GHOST_CLI_VERSION 1.9.9
RUN npm install -g "ghost-cli@$GHOST_CLI_VERSION"

ENV GHOST_INSTALL /var/lib/ghost
ENV GHOST_CONTENT /var/lib/ghost/content

ENV GHOST_VERSION 2.16.4

RUN set -ex; \
	mkdir -p "$GHOST_INSTALL"; \
	chown node:node "$GHOST_INSTALL"; \
	\
	su-exec node ghost install "$GHOST_VERSION" --db sqlite3 --storage s3 --no-prompt --no-stack --no-setup --dir "$GHOST_INSTALL";  \
	\
# Tell Ghost to listen on all ips and not prompt for additional configuration
	cd "$GHOST_INSTALL"; \
	su-exec node ghost config --ip 0.0.0.0 --port 2368 --no-prompt --db sqlite3 --url http://localhost:2368 --dbpath "$GHOST_CONTENT/data/ghost.db"; \
	su-exec node ghost config paths.contentPath "$GHOST_CONTENT"; \
	\
# make a config.json symlink for NODE_ENV=development (and sanity check that it's correct)
	su-exec node ln -s config.production.json "$GHOST_INSTALL/config.development.json"; \
	readlink -f "$GHOST_INSTALL/config.development.json"; \
	\
# need to save initial content for pre-seeding empty volumes
	mv "$GHOST_CONTENT" "$GHOST_INSTALL/content.orig"; \
	mkdir -p "$GHOST_CONTENT"; \
    su-exec node yarn add ghost-storage-adapter-s3; \
    mkdir -p "$GHOST_CONTENT/adapters/storage"; \
    mkdir -p "$GHOST_INSTALL/content/adapters/storage"; \
  	chown node:node "$GHOST_CONTENT"; \
    cp -r "node_modules/ghost-storage-adapter-s3" "$GHOST_CONTENT/adapters/storage/s3"; \
    cp -r "node_modules/ghost-storage-adapter-s3" "/var/lib/ghost/versions/2.16.4/core/server/adapters/storage/s3"; \
    cp -r "node_modules/ghost-storage-adapter-s3" "$GHOST_INSTALL/content/adapters/storage/s3"; \
	chown node:node "$GHOST_CONTENT"

RUN set -eux; \
# force install "sqlite3" manually since it's an optional dependency of "ghost"
# (which means that if it fails to install, like on ARM/ppc64le/s390x, the failure will be silently ignored and thus turn into a runtime error instead)
# see https://github.com/TryGhost/Ghost/pull/7677 for more details
	cd "$GHOST_INSTALL/current"; \
# scrape the expected version of sqlite3 directly from Ghost itself
	sqlite3Version="$(npm view . optionalDependencies.sqlite3)"; \
	if ! su-exec node yarn add "sqlite3@$sqlite3Version" --force; then \
# must be some non-amd64 architecture pre-built binaries aren't published for, so let's install some build deps and do-it-all-over-again
		apk add --no-cache --virtual .build-deps python make gcc g++ libc-dev; \
		\
		su-exec node yarn add "sqlite3@$sqlite3Version" --force --build-from-source; \
		\
		apk del --no-network .build-deps; \
	fi

WORKDIR $GHOST_INSTALL
VOLUME $GHOST_CONTENT

COPY config.production.json "$GHOST_INSTALL/config.production.json"
COPY docker-entrypoint.sh /usr/local/bin
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 2368
CMD ["node", "current/index.js"]
