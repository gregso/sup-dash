FROM python:3.9-slim

WORKDIR /app

# Install cron and dependencies
RUN apt-get update && apt-get -y install cron && rm -rf /var/lib/apt/lists/*

# Install DBT and Oracle client dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        unzip \
        libaio1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Oracle Instant Client
ARG ORACLE_VERSION=21_8
ARG ORACLE_DOWNLOAD_URL=https://download.oracle.com/otn_software/linux/instantclient/218000/instantclient-basiclite-linux.x64-21.8.0.0.0dbru.zip

WORKDIR /opt/oracle
RUN curl -Lo instantclient.zip ${ORACLE_DOWNLOAD_URL} \
    && unzip instantclient.zip \
    && rm instantclient.zip \
    && cd /opt/oracle/instantclient* \
    && echo /opt/oracle/instantclient* > /etc/ld.so.conf.d/oracle-instantclient.conf \
    && ldconfig

# Install Python dependencies
WORKDIR /app
RUN pip install --no-cache-dir dbt-core~=1.4.0 dbt-oracle~=1.4.0 pandas

# Copy scripts
COPY export_job.py /app/
COPY crontab /etc/cron.d/task-export-cron

# Give execution rights on the script
RUN chmod +x /app/export_job.py

# Give execution rights on the cron job
RUN chmod 0644 /etc/cron.d/task-export-cron

# Apply cron job
RUN crontab /etc/cron.d/task-export-cron

# Create log file
RUN touch /var/log/cron.log

# Run cron in foreground
CMD ["cron", "-f"]
