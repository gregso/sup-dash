FROM python:3.9-slim

WORKDIR /app

# Install required system dependencies for Oracle client
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        unzip \
        libaio1 \
        git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Download and install Oracle Instant Client (using basic instead of basiclite)
ARG ORACLE_VERSION=21_8
ARG ORACLE_DOWNLOAD_URL=https://download.oracle.com/otn_software/linux/instantclient/218000/instantclient-basic-linux.x64-21.8.0.0.0dbru.zip

WORKDIR /opt/oracle
RUN curl -Lo instantclient.zip ${ORACLE_DOWNLOAD_URL} \
    && unzip instantclient.zip \
    && rm instantclient.zip \
    && cd /opt/oracle/instantclient* \
    && echo /opt/oracle/instantclient* > /etc/ld.so.conf.d/oracle-instantclient.conf \
    && ldconfig

# Install DBT and Oracle adapter
WORKDIR /app
RUN pip install --no-cache-dir \
    dbt-core~=1.4.0 \
    dbt-oracle~=1.4.0

# Set environment variables for Oracle Instant Client
ENV LD_LIBRARY_PATH=/opt/oracle/instantclient_21_8
ENV ORACLE_HOME=/opt/oracle/instantclient_21_8
ENV PATH=$PATH:/opt/oracle/instantclient_21_8
# Either use this for thick mode with the basic package:
# ENV ORA_PYTHON_DRIVER_TYPE=thick
# Or this for thin mode (doesn't require client libraries):
ENV ORA_PYTHON_DRIVER_TYPE=thin

# Add entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["dbt", "run"]
