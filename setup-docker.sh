#!/bin/bash
# Create all directories and files for Docker setup

# Set up main directories
mkdir -p dbt/models dbt/macros
mkdir -p backend/app/api/endpoints backend/app/models backend/app/services backend/app/utils
mkdir -p frontend
mkdir -p scheduler
mkdir -p data/exports

# Create root level docker-compose.yml if it doesn't exist
if [ ! -f docker-compose.yml ]; then
    echo "Creating docker-compose.yml..."
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Data processing service (DBT)
  dbt:
    build:
      context: ./dbt
      dockerfile: Dockerfile
    volumes:
      - ./dbt:/app
      - ./data/exports:/data/exports
    environment:
      - DBT_ORACLE_USER=${DBT_ORACLE_USER}
      - DBT_ORACLE_PASSWORD=${DBT_ORACLE_PASSWORD}
      - DBT_ORACLE_HOST=${DBT_ORACLE_HOST}
      - DBT_ORACLE_PORT=${DBT_ORACLE_PORT}
      - DBT_ORACLE_SERVICE=${DBT_ORACLE_SERVICE}
      - DBT_ORACLE_SCHEMA=${DBT_ORACLE_SCHEMA}
    command: tail -f /dev/null # Keep container running for manual dbt execution

  # Ollama LLM service
  ollama:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    restart: unless-stopped
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

  # FastAPI Backend
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    volumes:
      - ./data/exports:/data/exports
    environment:
      - JWT_SECRET_KEY=${JWT_SECRET_KEY}
      - CSV_DIR=/data/exports
      - TASKS_CSV=tasks_daily.csv
      - LLM_PROVIDER=ollama
      - OLLAMA_BASE_URL=http://ollama:11434
      - OLLAMA_MODEL=${OLLAMA_MODEL:-llama3}
      - LLM_ENABLED=${LLM_ENABLED:-True}
      - CORS_ORIGINS=${CORS_ORIGINS:-http://localhost:3000,https://tasking-monitor.example.com}
    depends_on:
      - dbt
      - ollama

  # React Frontend
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    ports:
      - "3000:80"
    environment:
      - REACT_APP_API_URL=${API_URL:-http://localhost:8000/api}
    depends_on:
      - backend

  # Scheduled Jobs Service
  scheduler:
    build:
      context: ./scheduler
      dockerfile: Dockerfile
    volumes:
      - ./dbt:/app/dbt
      - ./data/exports:/data/exports
    environment:
      - DBT_ORACLE_USER=${DBT_ORACLE_USER}
      - DBT_ORACLE_PASSWORD=${DBT_ORACLE_PASSWORD}
      - DBT_ORACLE_HOST=${DBT_ORACLE_HOST}
      - DBT_ORACLE_PORT=${DBT_ORACLE_PORT}
      - DBT_ORACLE_SERVICE=${DBT_ORACLE_SERVICE}
      - DBT_ORACLE_SCHEMA=${DBT_ORACLE_SCHEMA}
    depends_on:
      - dbt

volumes:
  data:
  ollama_data:
EOF
fi

# Create DBT files
echo "Creating DBT Dockerfile..."
cat > dbt/Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Install required system dependencies for Oracle client
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        unzip \
        libaio1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Download and install Oracle Instant Client
ARG ORACLE_VERSION=21_8
ARG ORACLE_DOWNLOAD_URL=https://download.oracle.com/otn_software/linux/instantclient/218000/instantclient-basiclite-linux.x64-21.8.0.0.0dbru.zip

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

# Add entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["dbt", "run"]
EOF

echo "Creating DBT entrypoint script..."
cat > dbt/entrypoint.sh << 'EOF'
#!/bin/bash
# entrypoint.sh for DBT container

set -e

# Display DBT version
echo "Running with DBT version:"
dbt --version

# Check if we need to initialize a project
if [ ! -f dbt_project.yml ]; then
    echo "Initializing new DBT project..."
    dbt init task_monitoring

    # Ensure proper profile is configured
    sed -i 's/profile: .*/profile: task_monitoring/' dbt_project.yml
fi

# Display configuration
echo "DBT Oracle configuration:"
echo "User: $DBT_ORACLE_USER"
echo "Host: $DBT_ORACLE_HOST:$DBT_ORACLE_PORT"
echo "Service: $DBT_ORACLE_SERVICE"
echo "Schema: $DBT_ORACLE_SCHEMA"

# Create profiles.yml dynamically from environment variables
mkdir -p ~/.dbt
cat > ~/.dbt/profiles.yml << PROFILE
task_monitoring:
  outputs:
    dev:
      type: oracle
      user: "${DBT_ORACLE_USER}"
      password: "${DBT_ORACLE_PASSWORD}"
      host: "${DBT_ORACLE_HOST}"
      port: ${DBT_ORACLE_PORT}
      service: "${DBT_ORACLE_SERVICE}"
      schema: "${DBT_ORACLE_SCHEMA}"
      threads: 4
  target: dev
PROFILE

# Run the specified command
exec "$@"
EOF
chmod +x dbt/entrypoint.sh

# Create Backend files
echo "Creating Backend Dockerfile and scripts..."
cat > backend/Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Add Ollama setup script
COPY ollama-setup.sh /app/ollama-setup.sh
RUN chmod +x /app/ollama-setup.sh

# Add startup script to check Ollama and then run the application
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Create the directory structure
RUN mkdir -p app/api/endpoints app/models app/services app/utils

# Expose the port the app runs on
EXPOSE 8000

# Run the startup script
CMD ["/app/start.sh"]
EOF

# Create backend requirements.txt
cat > backend/requirements.txt << 'EOF'
fastapi>=0.68.0
uvicorn>=0.15.0
python-jose[cryptography]>=3.3.0
passlib[bcrypt]>=1.7.4
python-multipart>=0.0.5
pandas>=1.3.0
requests>=2.28.0
python-dotenv>=0.19.0
pytest>=6.2.5
httpx>=0.18.2
numpy>=1.23.0
EOF

# Create backend start script
cat > backend/start.sh << 'EOF'
#!/bin/bash
# start.sh - Backend startup script that ensures Ollama is ready before starting the application

# Check if LLM is enabled and provider is Ollama
if [ "${LLM_ENABLED,,}" = "true" ] && [ "${LLM_PROVIDER,,}" = "ollama" ]; then
    echo "LLM is enabled with Ollama provider. Setting up Ollama..."

    # Run the Ollama setup script
    /app/ollama-setup.sh

    # Check the return code
    if [ $? -ne 0 ]; then
        echo "Ollama setup failed. The application will continue, but LLM features may not work properly."
    else
        echo "Ollama setup completed successfully!"
    fi
else
    echo "Ollama setup skipped (LLM_ENABLED=$LLM_ENABLED, LLM_PROVIDER=$LLM_PROVIDER)"
fi

# Start the FastAPI application
echo "Starting the FastAPI application..."
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
EOF
chmod +x backend/start.sh

# Create Ollama setup script
cat > backend/ollama-setup.sh << 'EOF'
#!/bin/bash
# ollama-setup.sh - Script to setup Ollama models and perform initial configuration

# Ensure Ollama service is available
echo "Waiting for Ollama service to be ready..."
timeout=60
counter=0
while ! curl -s --head -f http://ollama:11434/api/health >/dev/null 2>&1; do
    if [ $counter -ge $timeout ]; then
        echo "Timed out waiting for Ollama to be ready"
        exit 1
    fi
    echo "Waiting for Ollama service... ($counter/$timeout)"
    sleep 1
    counter=$((counter+1))
done

echo "Ollama service is ready!"

# Check if specified model exists
MODEL=${OLLAMA_MODEL:-llama3}
echo "Checking if model $MODEL is available..."

if ! curl -s "http://ollama:11434/api/tags" | grep -q "\"name\":\"$MODEL\""; then
    echo "Model $MODEL not found. Pulling model..."

    # Pull the model
    curl -X POST http://ollama:11434/api/pull -d "{\"name\":\"$MODEL\"}"

    # Check if pull was successful
    if ! curl -s "http://ollama:11434/api/tags" | grep -q "\"name\":\"$MODEL\""; then
        echo "Failed to pull model $MODEL. Please check Ollama logs."
        echo "Available models:"
        curl -s "http://ollama:11434/api/tags" | jq -r '.models[].name'
        exit 1
    fi

    echo "Model $MODEL pulled successfully"
else
    echo "Model $MODEL is already available"
fi

# Create optimized task summarizer model
echo "Creating optimized task summarizer model..."

# Create Modelfile
cat > /tmp/Modelfile << EOL
FROM $MODEL
SYSTEM You are a task summarization assistant. Always provide concise, factual summaries focusing on key actions and deadlines. Limit your response to 1-2 sentences.
PARAMETER temperature 0.3
PARAMETER num_predict 100
EOL

# Create the model
curl -X POST http://ollama:11434/api/create -d "{
  \"name\": \"task-summarizer\",
  \"modelfile\": \"$(cat /tmp/Modelfile | base64 | tr -d '\n')\"
}"

echo "Task summarizer model created successfully"

# Display available models
echo "Available models:"
curl -s "http://ollama:11434/api/tags" | jq -r '.models[].name'

echo "Ollama setup completed successfully!"
EOF
chmod +x backend/ollama-setup.sh

# Create Frontend files
echo "Creating Frontend Dockerfile and Nginx config..."
cat > frontend/Dockerfile << 'EOF'
# Build stage
FROM node:16-alpine AS build

WORKDIR /app

# Copy package files and install dependencies
COPY package.json package-lock.json ./
RUN npm ci

# Copy source code and build the application
COPY . .
RUN npm run build

# Production stage
FROM nginx:alpine

# Copy the build output from build stage
COPY --from=build /app/build /usr/share/nginx/html

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
EOF

# Create Nginx config
cat > frontend/nginx.conf << 'EOF'
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    # Handle React routing
    location / {
        try_files $uri $uri/ /index.html;
    }

    # API proxy
    location /api/ {
        proxy_pass http://backend:8000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# Create dummy package.json for frontend to prevent Docker build error
cat > frontend/package.json << 'EOF'
{
  "name": "task-monitoring-frontend",
  "version": "0.1.0",
  "private": true,
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-router-dom": "^6.8.0",
    "axios": "^1.3.0",
    "recharts": "^2.3.2",
    "lucide-react": "^0.124.0"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "eslintConfig": {
    "extends": [
      "react-app",
      "react-app/jest"
    ]
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  }
}
EOF

touch frontend/package-lock.json

# Create Scheduler files
echo "Creating Scheduler Dockerfile and scripts..."
cat > scheduler/Dockerfile << 'EOF'
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
EOF

# Create crontab
cat > scheduler/crontab << 'EOF'
# Run the task export job every 2 hours
0 */2 * * * python /app/export_job.py >> /var/log/cron.log 2>&1
EOF

# Create export job script
cat > scheduler/export_job.py << 'EOF'
#!/usr/bin/env python
import os
import subprocess
import shutil
from datetime import datetime
import pandas as pd

# Configure paths
DBT_PATH = "/app/dbt"
EXPORT_DIR = "/data/exports"
TASKS_CSV = "tasks_daily.csv"

# Create export directory if it doesn't exist
os.makedirs(EXPORT_DIR, exist_ok=True)

# Set timestamp for this export
timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
print(f"Starting task export job at {timestamp}")

# Change to DBT directory and run DBT
os.chdir(DBT_PATH)
print("Running DBT export models...")
try:
    # Run DBT export models
    result = subprocess.run(
        ["dbt", "run", "--select", "exports.*"],
        check=True,
        capture_output=True,
        text=True
    )
    print(f"DBT run output: {result.stdout}")
except subprocess.CalledProcessError as e:
    print(f"Error running DBT: {e}")
    print(f"Error output: {e.stderr}")
    exit(1)

# Create timestamped copies of the export files
for file_name in [TASKS_CSV]:
    src = os.path.join(EXPORT_DIR, file_name)
    if os.path.exists(src):
        # Create timestamped backup
        backup = os.path.join(EXPORT_DIR, f"{file_name.split('.')[0]}_{timestamp}.csv")
        shutil.copy2(src, backup)
        print(f"Created backup at {backup}")

        # Process the file to add additional data if needed
        try:
            df = pd.read_csv(src)
            # You could add any additional processing here

            # Save the processed data back to the original file
            df.to_csv(src, index=False)
            print(f"Processed {file_name}")
        except Exception as e:
            print(f"Error processing {file_name}: {e}")
    else:
        print(f"Warning: Export file {src} not found")

print(f"Task export job completed at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
EOF

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "Creating .env file..."
    cat > .env << 'EOF'
# Oracle Database Configuration
DBT_ORACLE_USER=your_oracle_user
DBT_ORACLE_PASSWORD=your_oracle_password
DBT_ORACLE_HOST=your_oracle_host
DBT_ORACLE_PORT=1521
DBT_ORACLE_SERVICE=your_oracle_service
DBT_ORACLE_SCHEMA=GSOWA

# Backend Configuration
JWT_SECRET_KEY=your_secure_jwt_secret_key_change_this_in_production
CORS_ORIGINS=http://localhost:3000,https://tasking-monitor.example.com

# LLM Configuration - Ollama
LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://ollama:11434
OLLAMA_MODEL=phi
LLM_ENABLED=True

# Frontend Configuration
API_URL=http://localhost:8000/api
EOF
fi

echo "All Dockerfiles and configuration files have been created successfully!"
echo "You can now run 'docker-compose build' to build the images."
