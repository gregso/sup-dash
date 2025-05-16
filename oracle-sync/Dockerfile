FROM python:3.11-slim

# Install Oracle instant client
RUN apt-get update && apt-get install -y libaio1 wget unzip \
    && mkdir -p /opt/oracle \
    && cd /opt/oracle \
    && wget https://download.oracle.com/otn_software/linux/instantclient/instantclient-basiclite-linuxx64.zip \
    && unzip instantclient-basiclite-linuxx64.zip \
    && rm instantclient-basiclite-linuxx64.zip \
    && cd /opt/oracle/instantclient* \
    && ln -s libclntsh.so.19.1 libclntsh.so \
    && ln -s libocci.so.19.1 libocci.so

ENV LD_LIBRARY_PATH=/opt/oracle/instantclient_19_3:$LD_LIBRARY_PATH
ENV ORACLE_HOME=/opt/oracle/instantclient_19_3
ENV PATH=$PATH:$ORACLE_HOME

# Set working directory
WORKDIR /app

# Install uv for dependency management
RUN pip install uv

# Copy requirements and install dependencies
COPY requirements.txt .
RUN uv pip install -r requirements.txt

# Copy the wait script and make it executable
COPY wait-for-it.sh .
RUN chmod +x wait-for-it.sh

# Copy the sync script
COPY sync.py .

CMD ["python", "sync.py"]
