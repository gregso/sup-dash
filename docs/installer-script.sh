#!/bin/bash
# task-monitoring-installer.sh
# Complete installer script for Task Monitoring System

set -e  # Exit on error

echo "==============================================="
echo "  Task Monitoring System - Installer Script"
echo "==============================================="
echo ""
echo "This script will install and configure all components"
echo "of the Task Monitoring System."
echo ""

# Check for required tools
check_requirements() {
  echo "Checking requirements..."
  
  # Check for Docker
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed. Please install Docker first."
    echo "You can install it using Homebrew: brew install docker"
    exit 1
  fi
  
  # Check for Docker Compose
  if ! command -v docker-compose >/dev/null 2>&1; then
    echo "Docker Compose is not installed. Please install Docker Compose first."
    echo "You can install it using Homebrew: brew install docker-compose"
    exit 1
  fi
  
  # Check for Colima (macOS specific)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    if ! command -v colima >/dev/null 2>&1; then
      echo "Colima is not installed. We recommend using Colima for macOS."
      echo "You can install it using Homebrew: brew install colima"
      read -p "Do you want to continue without Colima? (y/n) " CONTINUE_WITHOUT_COLIMA
      if [[ ! $CONTINUE_WITHOUT_COLIMA =~ ^[Yy]$ ]]; then
        exit 1
      fi
    else
      # Check if Colima is running
      if ! colima status 2>/dev/null | grep -q "running"; then
        echo "Colima is not running. Starting Colima with optimized settings..."
        colima stop 2>/dev/null || true
        colima start --cpu 6 --memory 12 --disk 50 --vm-type=vz --mount-type=virtiofs
      fi
    fi
  fi
  
  echo "All requirements satisfied!"
}

# Create project directory structure
create_directory_structure() {
  echo "Creating directory structure..."
  
  # Create main directories
  mkdir -p dbt/models dbt/macros
  mkdir -p backend/app/api/endpoints backend/app/models backend/app/services backend/app/utils
  mkdir -p frontend
  mkdir -p scheduler
  mkdir -p data/exports
  
  echo "Directory structure created!"
}

# Create Docker files
create_docker_files() {
  echo "Creating Docker files..."
  
  # Create docker-compose.yml
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

  # Ollama LLM service - optimized for Apple Silicon/Colima
  ollama:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    restart: unless-stopped
    environment:
      - OLLAMA_ENABLE_METAL=1  # Enable Metal acceleration for Apple Silicon

  # FastAPI Backend
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    ports:
      - "8001:8000"
    volumes:
      - ./data/exports:/data/exports
    environment:
      - JWT_SECRET_KEY=${JWT_SECRET_KEY}
      - CSV_DIR=/data/exports
      - TASKS_CSV=tasks_daily.csv
      - LLM_PROVIDER=ollama
      - OLLAMA_BASE_URL=http://ollama:11434
      - OLLAMA_MODEL=${OLLAMA_MODEL:-llama3:8b-instruct}
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
      - REACT_APP_API_URL=${API_URL:-http://localhost:8001/api}
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

  # Create DBT Dockerfile
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

  # Create DBT entrypoint script
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

  # Create Backend Dockerfile
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

  # Create Backend requirements.txt
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

  # Create Backend start.sh
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
MODEL=${OLLAMA_MODEL:-llama3:8b-instruct}
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

  # Create Frontend Dockerfile
  cat > frontend/Dockerfile << 'EOF'
FROM nginx:alpine

# Create a simple HTML page
RUN echo '<html><body><h1>Task Monitoring Dashboard</h1><p>Placeholder for the real application.</p><div style="margin-top: 30px; padding: 20px; background-color: #f0f8ff; border-radius: 8px;"><h2>Features Coming Soon</h2><ul><li>Task overview and statistics</li><li>Live issue tracking</li><li>Department performance metrics</li><li>AI-powered task summarization</li></ul></div></body></html>' > /usr/share/nginx/html/index.html

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
EOF

  # Create Frontend nginx.conf
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

  # Create Scheduler Dockerfile
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

  # Create Scheduler crontab
  cat > scheduler/crontab << 'EOF'
# Run the task export job every 2 hours
0 */2 * * * python /app/export_job.py >> /var/log/cron.log 2>&1
EOF

  # Create Scheduler export job
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

  echo "Docker files created successfully!"
}

# Create DBT models
create_dbt_models() {
  echo "Creating DBT models..."
  
  # Create schema.yml
  cat > dbt/models/schema.yml << 'EOF'
version: 2

sources:
  - name: oracle
    database: "{{ env_var('DBT_ORACLE_SERVICE') }}"
    schema: "{{ env_var('DBT_ORACLE_SCHEMA') }}"
    tables:
      - name: SDRR_TASKACTIONS_CHAMPIONS
        description: "Combined tasks and actions view from Oracle"
        columns:
          - name: TASK_ID
            description: "Unique identifier for the task"
          - name: CLIENT
            description: "Client associated with the task"
          - name: HISTORY
            description: "Task history"
          - name: STATUS12
            description: "Status of the task"
          - name: CREATEDDATETIME
            description: "When the task was created"
          - name: GROUP
            description: "Group information"
          - name: COMPANY
            description: "Company information"
          - name: POSITION
            description: "Position information"
          - name: JOB_CLASSIFICATION
            description: "Job classification"
          - name: EMAIL
            description: "Employee email"
          - name: DEPT_DESCR
            description: "Department handling the task"
          - name: DIV_DESCR
            description: "Division handling the task"
          - name: LIVEISSUE
            description: "Flag indicating if task is a live issue (Y/N)"
          - name: TASK_CLASS
            description: "Task classification"
          - name: ACT_NUMBER
            description: "Number of actions for this task"
          - name: PR_AC_SORT
            description: "Action sort order"
          - name: VIEWYN
            description: "Action visibility flag"
          - name: ACTDATETIME
            description: "When the action was performed"
          - name: ACTIONCODE12
            description: "Code representing the action type"
          - name: ACTEMPL
            description: "Employee who performed the action"
          - name: ASSIGNEDTO
            description: "Employee assigned to the task"
          - name: TMS_TASK_ID
            description: "Task ID in the TMS system"
          - name: PRODUCT
            description: "Product information"

models:
  - name: task_analytics
    description: "Processed task data for analytics"
    columns:
      - name: task_id
        description: "Unique identifier for the task"
        tests:
          - not_null
      - name: client
        description: "Client associated with the task"
        tests:
          - not_null
      - name: live_issue
        description: "Flag indicating if task is a live issue (Y/N)"
      - name: created_datetime
        description: "When the task was created"
      - name: last_action_datetime
        description: "When the task was last actioned"
      - name: last_action_code
        description: "Code of the last action"
      - name: last_action_employee
        description: "Employee who performed the last action"
      - name: department
        description: "Department handling the task"
      - name: assigned_to
        description: "Employee assigned to the task"
      - name: days_since_last_action
        description: "Number of days since last action"
      - name: product
        description: "Product information"
      - name: task_class
        description: "Task classification"
      - name: status
        description: "Status of the task"
      - name: division
        description: "Division handling the task"

  - name: exports_tasks_daily
    description: "Daily CSV export of task analytics data"
    config:
      post-hook: 
        - "{{ export_csv('exports_tasks_daily', '/data/exports/tasks_daily.csv') }}"
    columns:
      - name: task_id
        description: "Unique identifier for the task"
      - name: client
        description: "Client associated with the task"
      # (rest of columns from task_analytics)
EOF

  # Create task_analytics.sql
  cat > dbt/models/task_analytics.sql << 'EOF'
WITH task_latest_actions AS (
    -- Get the latest action for each task
    SELECT
        TASK_ID,
        CLIENT,
        MAX(ACTDATETIME) as last_action_datetime
    FROM
        {{ source('oracle', 'SDRR_TASKACTIONS_CHAMPIONS') }}
    GROUP BY
        TASK_ID, CLIENT
),

task_actions_ranked AS (
    -- Join to get the details for the latest action and rank actions
    SELECT
        t.TASK_ID,
        t.CLIENT,
        t.LIVEISSUE,
        t.CREATEDDATETIME as created_datetime,
        la.last_action_datetime,
        a.ACTIONCODE12 as last_action_code,
        a.ACTEMPL as last_action_employee,
        a.DEPT_DESCR as department,
        a.ASSIGNEDTO as assigned_to,
        a.DIV_DESCR as division,
        a.JOB_CLASSIFICATION as job_classification,
        t.STATUS12 as status,
        t.PRODUCT as product,
        t.TASK_CLASS as task_class,
        ROW_NUMBER() OVER (PARTITION BY t.TASK_ID, t.CLIENT ORDER BY a.PR_AC_SORT DESC) as action_rank
    FROM
        {{ source('oracle', 'SDRR_TASKACTIONS_CHAMPIONS') }} t
    -- Join to get the latest action time
    JOIN
        task_latest_actions la 
            ON t.TASK_ID = la.TASK_ID 
            AND t.CLIENT = la.CLIENT
    -- Join again to get details of the latest action
    JOIN
        {{ source('oracle', 'SDRR_TASKACTIONS_CHAMPIONS') }} a
            ON t.TASK_ID = a.TASK_ID
            AND t.CLIENT = a.CLIENT
            AND la.last_action_datetime = a.ACTDATETIME
)

SELECT
    TASK_ID as task_id,
    CLIENT as client,
    LIVEISSUE as live_issue,
    created_datetime,
    last_action_datetime,
    last_action_code,
    last_action_employee,
    department,
    assigned_to,
    division,
    job_classification,
    status,
    product,
    task_class,
    DATEDIFF('day', last_action_datetime, CURRENT_TIMESTAMP()) as days_since_last_action
FROM
    task_actions_ranked
WHERE
    action_rank = 1
EOF

  # Create exports_tasks_daily.sql
  cat > dbt/models/exports_tasks_daily.sql << 'EOF'
SELECT * FROM {{ ref('task_analytics') }}
EOF

  # Create export_csv.sql macro
  mkdir -p dbt/macros
  cat > dbt/macros/export_csv.sql << 'EOF'
{% macro export_csv(model_name, output_path) %}
{% set csv_query %}
COPY (
    SELECT * FROM {{ ref(model_name) }}
) TO '{{ output_path }}' WITH CSV HEADER;
{% endset %}

{% do run_query(csv_query) %}
{% endmacro %}
EOF

  # Create dbt_project.yml
  cat > dbt/dbt_project.yml << 'EOF'
name: 'task_monitoring'
version: '1.0.0'
config-version: 2

profile: 'task_monitoring'

model-paths: ["models"]
analysis-paths: ["analyses"]
test-paths: ["tests"]
seed-paths: ["seeds"]
macro-paths: ["macros"]
snapshot-paths: ["snapshots"]

target-path: "target"
clean-targets:
  - "target"
  - "dbt_packages"

models:
  task_monitoring:
    materialized: table
    exports:
      +materialized: table
      schema: exports
EOF

  echo "DBT models created successfully!"
}

# Create Backend files
create_backend_files() {
  echo "Creating Backend API files..."
  
  # Create main.py
  mkdir -p backend/app
  cat > backend/app/main.py << 'EOF'
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer

from app.api.endpoints import tasks, analytics, auth
from app.config import settings

app = FastAPI(
    title="Task Monitoring API",
    description="API for task monitoring dashboard",
    version="1.0.0"
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(auth.router, prefix="/api", tags=["auth"])
app.include_router(tasks.router, prefix="/api", tags=["tasks"])
app.include_router(analytics.router, prefix="/api", tags=["analytics"])

@app.get("/")
async def root():
    return {"message": "Task Monitoring API Service"}

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
EOF

  # Create config.py
  cat > backend/app/config.py << 'EOF'
import os
from typing import List
from pydantic import AnyHttpUrl, BaseSettings

class Settings(BaseSettings):
    API_V1_STR: str = "/api/v1"
    JWT_SECRET_KEY: str = os.getenv("JWT_SECRET_KEY", "change_this_in_production")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days
    
    # CORS
    CORS_ORIGINS: List[AnyHttpUrl] = [
        "http://localhost:3000",  # Frontend development
        "https://tasking-monitor.example.com",  # Production
    ]
    
    # CSV Settings
    CSV_DIR: str = os.getenv("CSV_DIR", "/data/exports")
    TASKS_CSV: str = os.getenv("TASKS_CSV", "tasks_daily.csv")
    
    # LLM Settings
    LLM_PROVIDER: str = os.getenv("LLM_PROVIDER", "ollama")  # 'ollama' or 'openai'
    LLM_ENABLED: bool = os.getenv("LLM_ENABLED", "True").lower() in ("true", "1", "t")
    
    # Ollama Settings
    OLLAMA_BASE_URL: str = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434")
    OLLAMA_MODEL: str = os.getenv("OLLAMA_MODEL", "llama3:8b-instruct")
    
    # OpenAI Settings (fallback)
    OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
    OPENAI_MODEL: str = os.getenv("OPENAI_MODEL", "gpt-3.5-turbo")
    
    class Config:
        case_sensitive = True
        env_file = ".env"

settings = Settings()
EOF

  # Create LLM service
  mkdir -p backend/app/services
  cat > backend/app/services/llm_service.py << 'EOF'
import os
import json
import requests
from typing import Optional, Dict, Any

from app.config import settings

class LLMService:
    def __init__(self):
        self.provider = settings.LLM_PROVIDER.lower()
        self.enabled = settings.LLM_ENABLED
        
        # Ollama configuration
        if self.provider == 'ollama':
            self.ollama_base_url = settings.OLLAMA_BASE_URL
            self.ollama_model = settings.OLLAMA_MODEL
        
        # OpenAI configuration (as fallback)
        elif self.provider == 'openai':
            self.openai_api_key = settings.OPENAI_API_KEY
            self.openai_model = settings.OPENAI_MODEL
            
            if self.openai_api_key:
                import openai
                openai.api_key = self.openai_api_key
        
    def summarize_task(self, task_content: str) -> Optional[str]:
        """Generate a summary of task content using the configured LLM provider"""
        if not self.enabled or not task_content:
            return None
            
        if self.provider == 'ollama':
            return self._summarize_with_ollama(task_content)
        elif self.provider == 'openai':
            return self._summarize_with_openai(task_content)
        else:
            print(f"Unsupported LLM provider: {self.provider}")
            return None

    def _summarize_with_ollama(self, task_content: str) -> Optional[str]:
        """Generate a summary using Ollama local LLM"""
        try:
            prompt = f"""
            Please provide a concise summary (maximum 2 sentences) of the following task content:
            
            {task_content}
            
            Focus on the key details and action items only.
            """
            
            # Make request to Ollama API
            response = requests.post(
                f"{self.ollama_base_url}/api/generate",
                json={
                    "model": self.ollama_model,
                    "prompt": prompt,
                    "system": "You are a helpful assistant that summarizes task content concisely.",
                    "stream": False,
                    "options": {
                        "temperature": 0.3,
                        "num_predict": 100  # Limit output tokens
                    }
                }
            )
            
            if response.status_code == 200:
                result = response.json()
                summary = result.get('response', '').strip()
                return summary
            else:
                print(f"Error from Ollama: {response.text}")
                return None
                
        except Exception as e:
            print(f"Error generating summary with Ollama: {e}")
            return None

    def _summarize_with_openai(self, task_content: str) -> Optional[str]:
        """Generate a summary using OpenAI API (fallback)"""
        if not self.openai_api_key:
            return None
            
        try:
            import openai
            
            prompt = f"""
            Please provide a concise summary (maximum 2 sentences) of the following task content:
            
            {task_content}
            
            Focus on the key details and action items only.
            """
            
            response = openai.ChatCompletion.create(
                model=self.openai_model,
                messages=[
                    {"role": "system", "content": "You are a helpful assistant that summarizes task content concisely."},
                    {"role": "user", "content": prompt}
                ],
                max_tokens=100,
                temperature=0.3
            )
            
            summary = response.choices[0].message.content.strip()
            return summary
            
        except Exception as e:
            print(f"Error generating summary with OpenAI: {e}")
            return None
EOF

  # Create minimal endpoint files
  mkdir -p backend/app/api/endpoints
  touch backend/app/api/endpoints/__init__.py

  cat > backend/app/api/endpoints/auth.py << 'EOF'
from fastapi import APIRouter

router = APIRouter()

@router.get("/auth/status")
async def auth_status():
    return {"status": "Authentication service running"}
EOF

  cat > backend/app/api/endpoints/tasks.py << 'EOF'
from fastapi import APIRouter

router = APIRouter()

@router.get("/tasks")
async def get_tasks():
    return {"status": "Tasks endpoint running", "message": "This will return task data from the CSV files"}
EOF

  cat > backend/app/api/endpoints/analytics.py << 'EOF'
from fastapi import APIRouter

router = APIRouter()

@router.get("/analytics/stats")
async def get_stats():
    return {"status": "Analytics endpoint running", "message": "This will return analytics data from the CSV files"}
EOF

  # Create __init__.py files
  touch backend/app/__init__.py
  touch backend/app/api/__init__.py
  mkdir -p backend/app/models
  touch backend/app/models/__init__.py
  touch backend/app/services/__init__.py
  mkdir -p backend/app/utils
  touch backend/app/utils/__init__.py

  echo "Backend API files created successfully!"
}

# Create .env file
create_env_file() {
  echo "Creating .env file..."

  # Prompt user for database credentials
  echo "Please enter your Oracle database credentials:"
  read -p "Oracle User: " DB_USER
  read -sp "Oracle Password: " DB_PASSWORD
  echo ""
  read -p "Oracle Host: " DB_HOST
  read -p "Oracle Port [1521]: " DB_PORT
  DB_PORT=${DB_PORT:-1521}
  read -p "Oracle Service: " DB_SERVICE
  read -p "Oracle Schema: " DB_SCHEMA
  
  # Generate a random JWT secret key
  JWT_SECRET=$(openssl rand -hex 32)
  
  # Create .env file
  cat > .env << EOF
# Oracle Database Configuration
DBT_ORACLE_USER=${DB_USER}
DBT_ORACLE_PASSWORD=${DB_PASSWORD}
DBT_ORACLE_HOST=${DB_HOST}
DBT_ORACLE_PORT=${DB_PORT}
DBT_ORACLE_SERVICE=${DB_SERVICE}
DBT_ORACLE_SCHEMA=${DB_SCHEMA}

# Backend Configuration
JWT_SECRET_KEY=${JWT_SECRET}
CORS_ORIGINS=http://localhost:3000,https://tasking-monitor.example.com

# LLM Configuration - Ollama
LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://ollama:11434
OLLAMA_MODEL=llama3:8b-instruct
LLM_ENABLED=True

# Frontend Configuration
API_URL=http://localhost:8001/api
EOF

  echo ".env file created successfully!"
}

# Build and start the system
build_and_start() {
  echo "Building and starting the system..."
  
  # Check if ports are in use
  PORT_8001=$(lsof -i:8001 -t 2>/dev/null)
  PORT_3000=$(lsof -i:3000 -t 2>/dev/null)
  PORT_11434=$(lsof -i:11434 -t 2>/dev/null)
  
  if [ -n "$PORT_8001" ] || [ -n "$PORT_3000" ] || [ -n "$PORT_11434" ]; then
    echo "Warning: One or more required ports are already in use:"
    [ -n "$PORT_8001" ] && echo "- Port 8001 is in use by PID $PORT_8001"
    [ -n "$PORT_3000" ] && echo "- Port 3000 is in use by PID $PORT_3000"
    [ -n "$PORT_11434" ] && echo "- Port 11434 is in use by PID $PORT_11434"
    
    read -p "Do you want to continue anyway? (y/n) " CONTINUE_WITH_PORTS
    if [[ ! $CONTINUE_WITH_PORTS =~ ^[Yy]$ ]]; then
      echo "Please free up the required ports and run the installer again."
      exit 1
    fi
  fi
  
  # Build Docker images
  docker-compose build
  
  # Start services
  docker-compose up -d
  
  echo "System has been built and started!"
}

# Run tests
run_tests() {
  echo "Running basic tests..."
  
  # Check if containers are running
  echo "Checking if containers are running..."
  if ! docker-compose ps | grep -q "Up"; then
    echo "Error: Containers are not running properly."
    echo "Please check the logs with: docker-compose logs"
    exit 1
  fi
  
  # Test Backend API
  echo "Testing Backend API..."
  sleep 5  # Give the backend time to start
  HEALTH_CHECK=$(curl -s http://localhost:8001/health || echo "Failed")
  if [[ "$HEALTH_CHECK" == *"healthy"* ]]; then
    echo "✅ Backend API is running"
  else
    echo "❌ Backend API is not responding. Check logs with: docker-compose logs backend"
  fi
  
  # Test Frontend
  echo "Testing Frontend..."
  FRONTEND_CHECK=$(curl -s -I http://localhost:3000 | head -n 1 || echo "Failed")
  if [[ "$FRONTEND_CHECK" == *"200"* ]]; then
    echo "✅ Frontend is running"
  else
    echo "❌ Frontend is not responding. Check logs with: docker-compose logs frontend"
  fi
  
  # Test Ollama
  echo "Testing Ollama..."
  OLLAMA_CHECK=$(curl -s http://localhost:11434/api/health || echo "Failed")
  if [[ "$OLLAMA_CHECK" == *"ok"* ]]; then
    echo "✅ Ollama is running"
  else
    echo "❌ Ollama is not responding. Check logs with: docker-compose logs ollama"
  fi
  
  echo "Basic tests completed!"
}

# Print final instructions
print_instructions() {
  echo ""
  echo "==============================================="
  echo "   Task Monitoring System - Setup Complete!"
  echo "==============================================="
  echo ""
  echo "Your system is now running and can be accessed at:"
  echo "- Frontend: http://localhost:3000"
  echo "- Backend API: http://localhost:8001"
  echo "- Ollama API: http://localhost:11434"
  echo ""
  echo "Next steps:"
  echo "1. Run DBT to generate initial data:"
  echo "   docker-compose exec dbt dbt run"
  echo ""
  echo "2. Explore the API endpoints:"
  echo "   curl http://localhost:8001/api/tasks"
  echo ""
  echo "3. Check logs if you encounter any issues:"
  echo "   docker-compose logs [service_name]"
  echo ""
  echo "4. Stop the system when not in use:"
  echo "   docker-compose down"
  echo ""
  echo "For more detailed documentation, refer to the provided guides."
}

# Main installation flow
main() {
  check_requirements
  create_directory_structure
  create_docker_files
  create_dbt_models
  create_backend_files
  create_env_file
  build_and_start
  run_tests
  print_instructions
}

# Run the installer
main
