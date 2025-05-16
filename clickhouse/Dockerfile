FROM clickhouse/clickhouse-server:latest

COPY ./config/config.xml /etc/clickhouse-server/config.xml
COPY ./config/users.xml /etc/clickhouse-server/users.xml
COPY ./init /docker-entrypoint-initdb.d/

# Fix permissions before switching user
RUN chmod 644 /etc/clickhouse-server/config.xml /etc/clickhouse-server/users.xml && \
    chmod -R 755 /docker-entrypoint-initdb.d/

USER clickhouse
