# Task Monitoring System: Installation and Configuration Guide

This comprehensive guide provides step-by-step instructions for installing, configuring, and testing all components of the Task Monitoring System. Follow these instructions carefully to ensure a smooth setup process.

## Table of Contents

1. [Introduction and System Overview](#1-introduction-and-system-overview)
2. [Prerequisites](#2-prerequisites)
3. [Project Setup](#3-project-setup)
4. [Colima Configuration](#4-colima-configuration)
5. [Docker Environment Configuration](#5-docker-environment-configuration)
6. [Building and Starting the System](#6-building-and-starting-the-system)
7. [DBT Configuration](#7-dbt-configuration)
8. [Backend API Configuration and Testing](#8-backend-api-configuration-and-testing)
9. [Ollama LLM Setup](#9-ollama-llm-setup)
10. [Frontend Testing](#10-frontend-testing)
11. [Scheduler Configuration](#11-scheduler-configuration)
12. [Integration Testing](#12-integration-testing)
13. [Production Considerations](#13-production-considerations)
14. [Troubleshooting Guide](#14-troubleshooting-guide)
15. [Maintenance and Updates](#15-maintenance-and-updates)

## 1. Introduction and System Overview

The Task Monitoring System provides a complete solution for tracking and monitoring tasks across your organization. The system consists of:

- **DBT Data Transformation Layer**: Transforms Oracle data into analytics-ready formats
- **Backend API**: FastAPI service that handles data processing and LLM integration
- **Ollama LLM Service**: Local AI model for task summarization
- **Frontend Dashboard**: Web interface for visualizing task data
- **Scheduler**: Automates regular data refresh

## 2. Prerequisites

Before proceeding, ensure you have:

- **MacBook Pro M2 with 32GB RAM** (recommended)
- **macOS Ventura or later**
- **[Homebrew](https://brew.sh/)** package manager
- **Oracle database** access credentials
- **Git** for version control
- **Terminal** proficiency

Install the core dependencies:

```bash
# Install Docker and Colima
brew install docker docker-compose colima

# Install Git (if not already installed)
brew install git

# Optional: Install jq for JSON processing
brew install jq
```

## 3. Project Setup

Create and navigate to your project directory:

```bash
# Create project directory
mkdir task-monitoring-system
cd task-monitoring-system

# Initialize Git repository (optional)
git init
```

Clone the repository (if applicable) or create the file structure:

```bash
# Create directory structure
mkdir -p dbt/models dbt/macros
mkdir -p backend/app/api/endpoints backend/app/models backend/app/services backend/app/utils
mkdir -p frontend
mkdir -p scheduler
mkdir -p data/exports
```

Create the setup scripts:

```bash
# Download the setup scripts
curl -O https://raw.githubusercontent.com/yourusername/task-monitoring-system/main/setup-docker.sh
chmod +x setup-docker.sh

# Run the docker setup script
./setup-docker.sh
```

If you don't have the scripts from a repository, create them manually using the content provided in previous messages.

## 4. Colima Configuration

Configure Colima with optimized settings for your M2 MacBook Pro:

```bash
# Stop any running Colima instance
colima stop

# Start Colima with optimized settings
colima start --cpu 8 --memory 16 --disk 60 --vm-type=vz --vz-rosetta --mount-type=virtiofs
```

Verify Colima is running correctly:

```bash
# Check Colima status
colima status

# Ensure Docker can connect
docker info
```

## 5. Docker Environment Configuration

Create or update the .env file with your specific configuration:

```bash
# Create .env file if not already created by setup script
touch .env

# Fill it with your configuration values
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
OLLAMA_MODEL=llama3:8b-instruct
LLM_ENABLED=True

# Frontend Configuration
API_URL=http://localhost:8001/api
EOF
```

Check for port conflicts with ports 8001 and 3000:

```bash
# Check for port conflicts
lsof -i :8001 -i :3000 -i :11434
```

If any ports are in use, either stop the process using them or modify the docker-compose.yml to use different ports.

## 6. Building and Starting the System

Build the Docker images:

```bash
# Build all containers
docker-compose build
```

Start the system:

```bash
# Start all services in detached mode
docker-compose up -d
```

Verify all containers are running:

```bash
# Check container status
docker-compose ps

# Check logs for any errors
docker-compose logs
```

## 7. DBT Configuration

Configure the DBT models for your Oracle view:

1. Verify the existing models in the `dbt/models` directory match your database schema
2. Check or create the DBT project configuration:

```bash
# Ensure the dbt_project.yml file exists
cat dbt/dbt_project.yml
```

Execute DBT to verify database connectivity and generate the initial CSV exports:

```bash
# Enter the DBT container
docker-compose exec dbt bash

# Test the Oracle connection
dbt debug

# Run the models to generate the initial CSV files
dbt run

# Exit the container
exit
```

Verify the CSV exports were created:

```bash
# Check for generated CSV files
ls -l data/exports
```

## 8. Backend API Configuration and Testing

Verify the backend is running correctly:

```bash
# Check backend logs
docker-compose logs backend

# Test the backend API health endpoint
curl http://localhost:8001/health
```

Test API endpoints (adjust if you implemented authentication):

```bash
# Get task statistics
curl http://localhost:8001/api/analytics/stats

# Get list of tasks
curl http://localhost:8001/api/tasks
```

## 9. Ollama LLM Setup

Check if Ollama is running and the model has been downloaded:

```bash
# Check Ollama logs
docker-compose logs ollama

# List installed models
docker-compose exec ollama ollama list
```

If the model hasn't been downloaded automatically:

```bash
# Pull the model manually
docker-compose exec ollama ollama pull llama3:8b-instruct
```

Create a custom model optimized for task summarization:

```bash
# Create a Modelfile
echo "FROM llama3:8b-instruct
SYSTEM You are a task summarization assistant. Always provide concise, factual summaries focusing on key actions and deadlines. Limit your response to 1-2 sentences.
PARAMETER temperature 0.3
PARAMETER num_predict 100" > Modelfile

# Create the model
docker-compose exec -T ollama ollama create task-summarizer:latest - < Modelfile
```

Update the OLLAMA_MODEL in .env to use this custom model:

```bash
# Update the .env file
sed -i '' 's/OLLAMA_MODEL=.*/OLLAMA_MODEL=task-summarizer/' .env

# Restart the backend to use the new model
docker-compose restart backend
```

## 10. Frontend Testing

Verify the frontend is accessible:

```bash
# Open the frontend in your browser
open http://localhost:3000
```

At this point, you should see the placeholder dashboard. This will be replaced with a proper React application in a future development phase.

## 11. Scheduler Configuration

Verify the scheduler is configured to run the data export job:

```bash
# Check scheduler logs
docker-compose logs scheduler

# View the crontab configuration
docker-compose exec scheduler crontab -l
```

Test the export job manually:

```bash
# Run the export job manually
docker-compose exec scheduler python /app/export_job.py

# Check for updated CSV files
ls -la data/exports
```

## 12. Integration Testing

Perform integration testing to ensure all components work together:

1. Verify data flow:
   - DBT creates CSV files
   - Backend API reads CSV files
   - Frontend displays data from API

2. Test task summarization:
   - Create a sample task with content
   - Verify Ollama summarizes it correctly

3. Test data refresh:
   - Modify database data
   - Run scheduler job
   - Verify changes appear in the dashboard

## 13. Production Considerations

For production deployment, consider:

1. **Security**:
   - Use HTTPS with proper certificates
   - Implement proper authentication
   - Store sensitive credentials in a secure vault

2. **Backup**:
   - Set up regular database backups
   - Back up the Docker volumes

3. **Monitoring**:
   - Implement proper logging
   - Set up alerts for system failures

4. **Scaling**:
   - Configure container resource limits
   - Consider using a container orchestration system like Kubernetes

## 14. Troubleshooting Guide

### Common Issues and Solutions

#### Port Conflicts

```bash
# Create a port conflict resolution script
cat > fix-port.sh << 'EOF'
#!/bin/bash
# Find what's using the port
lsof -i :8001 -P -n
# Change port in docker-compose.yml if needed
sed -i '' 's/"8001:8000"/"8002:8000"/' docker-compose.yml
EOF
chmod +x fix-port.sh
```

#### Docker Build Failures

```bash
# Clean Docker cache and rebuild
docker-compose build --no-cache
```

#### DBT Connection Issues

```bash
# Test database connection directly
docker-compose exec dbt bash -c "python -c \"import cx_Oracle; cx_Oracle.connect('${DBT_ORACLE_USER}/${DBT_ORACLE_PASSWORD}@${DBT_ORACLE_HOST}:${DBT_ORACLE_PORT}/${DBT_ORACLE_SERVICE}')\""
```

#### Ollama Model Download Issues

```bash
# Check Ollama logs
docker-compose logs ollama

# Try pulling a smaller model
docker-compose exec ollama ollama pull phi
```

## 15. Maintenance and Updates

### Updating Models

To update DBT models:

```bash
# Update model files
nano dbt/models/task_analytics.sql

# Re-run DBT
docker-compose exec dbt dbt run
```

### Updating Docker Images

```bash
# Pull latest images
docker-compose pull

# Rebuild containers
docker-compose build

# Restart the system
docker-compose down
docker-compose up -d
```

### Backing Up and Restoring Data

```bash
# Backup data
mkdir -p backups
docker-compose exec dbt bash -c "cat /data/exports/tasks_daily.csv" > backups/tasks_$(date +%Y%m%d).csv

# Restore data
cat backups/tasks_20250515.csv > data/exports/tasks_daily.csv
```

### Checking System Health

```bash
# Create a health check script
cat > health_check.sh << 'EOF'
#!/bin/bash
echo "Checking system health..."
echo "Container status:"
docker-compose ps
echo "API health:"
curl -s http://localhost:8001/health
echo "Data files:"
ls -la data/exports
EOF
chmod +x health_check.sh
```

## Conclusion

You have successfully set up and configured the Task Monitoring System. This system provides a comprehensive solution for tracking and monitoring tasks across your organization, with features like:

- Real-time task monitoring
- Live issue tracking
- AI-powered task summarization
- Department performance metrics
- Automated data refresh

For further customization and development, refer to the provided scripts and configuration files. If you encounter any issues, consult the troubleshooting section or check the logs for more detailed information.
