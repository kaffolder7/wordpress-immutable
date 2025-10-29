FROM composer:2
# We isolate composer home/cache inside the container (not persisted) for speed
WORKDIR /work
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]