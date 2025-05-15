#!/bin/bash
# Script to optimize for MacBook Pro M2 with Colima

# Create a backup of the original docker-compose.yml
cp docker-compose.yml docker-compose.yml.bak

# Replace the docker-compose.yml file with M2-optimized version for Colima
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

  # Ollama LLM service - optimized for Colima on Apple Silicon
  ollama:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    restart: unless-stopped
    # When using Colima, hardware acceleration for Ollama is done at the VM level
    # No NVIDIA GPU requirements or specific environment variables needed here

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
      - OLLAMA_MODEL=${OLLAMA_MODEL:-llama3:8b-instruct}  # Better model for M2 with 32GB RAM
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

# Update the .env file to use a better model for M2
if grep -q "OLLAMA_MODEL=" .env; then
  # Replace existing OLLAMA_MODEL with new value
  sed -i '' 's/OLLAMA_MODEL=.*/OLLAMA_MODEL=llama3:8b-instruct/' .env 2>/dev/null || sed -i 's/OLLAMA_MODEL=.*/OLLAMA_MODEL=llama3:8b-instruct/' .env
else
  # Add OLLAMA_MODEL if it doesn't exist
  echo "OLLAMA_MODEL=llama3:8b-instruct" >> .env
fi

echo "Configuration has been optimized for MacBook Pro M2 with Colima!"
echo "A backup of the original file has been saved as docker-compose.yml.bak"
echo "The OLLAMA_MODEL in .env has been set to llama3:8b-instruct, which works well with M2 and 32GB RAM"
echo ""
echo "IMPORTANT: Before starting your services, you may want to stop and reconfigure Colima with:"
echo ""
echo "colima stop"
echo "colima start --cpu 6 --memory 16 --disk 50 --vm-type=vz --vz-rosetta"
echo ""
echo "After reconfiguring Colima, run 'docker-compose up -d' to start the services"
