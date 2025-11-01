ARG COMPOSER_IMAGE="composer:2@sha256:5248900ab8b5f7f880c2d62180e40960cd87f60149ec9a1abfd62ac72a02577c"   # default as a fallback
FROM ${COMPOSER_IMAGE}

LABEL org.opencontainers.image.title="wp-vendor-builder" \
      org.opencontainers.image.description="Deterministic Composer builder for WordPress vendor packages and theme; produces prebuilt /opt/vendor and wp-content for immutable runtime." \
      org.opencontainers.image.url="https://github.com/kaffolder7/wp-immutable" \
      org.opencontainers.image.source="https://github.com/kaffolder7/wp-immutable" \
      org.opencontainers.image.documentation="https://github.com/kaffolder7/wp-immutable#readme" \
      org.opencontainers.image.licenses="MIT"

# optional: jq is handy for JSON merge; tini for clean signal handling
RUN apk add --no-cache jq tini

# We isolate composer home/cache inside the container (not persisted) for speed
WORKDIR /work
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/sbin/tini","--","/entrypoint.sh"]