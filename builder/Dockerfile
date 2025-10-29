FROM composer:2

# optional: jq is handy for JSON merge; tini for clean signal handling
RUN apk add --no-cache jq tini

# We isolate composer home/cache inside the container (not persisted) for speed
WORKDIR /work
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/sbin/tini","--","/entrypoint.sh"]