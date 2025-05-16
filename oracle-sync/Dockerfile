FROM python:3.12-slim

# Install required OS dependencies
RUN apt-get update && apt-get install -y \
    libaio1 \
    wget \
    unzip \
    curl \
    build-essential \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*


# Download and install Oracle Instant Client
WORKDIR /opt/oracle
RUN wget https://download.oracle.com/otn_software/linux/instantclient/1926000/instantclient-basic-linux.x64-19.26.0.0.0dbru.zip && \
    unzip instantclient-basic-linux.x64-19.26.0.0.0dbru.zip

RUN rm instantclient-basic-linux.x64-19.26.0.0.0dbru.zip


# Set Oracle environment variables
ENV ORACLE_HOME=/opt/oracle/instantclient_19_26
ENV DOCKER_CONTAINER=1
ENV LD_LIBRARY_PATH=$ORACLE_HOME:$LD_LIBRARY_PATH
ENV PATH=$ORACLE_HOME:$PATH
# Set working directory
WORKDIR /app


# Copy requirements.txt and install dependencies
# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the sync script
COPY sync.py .

CMD ["python", "sync.py"]
