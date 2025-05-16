# Task Monitoring System Component Testing Guide

This guide provides detailed testing procedures for each component of the Task Monitoring System. Follow these step-by-step instructions to verify that each part of the system is functioning correctly.

## Table of Contents

1. [DBT Component Testing](#1-dbt-component-testing)
2. [Backend API Component Testing](#2-backend-api-component-testing)
3. [Ollama LLM Component Testing](#3-ollama-llm-component-testing)
4. [Frontend Component Testing](#4-frontend-component-testing)
5. [Scheduler Component Testing](#5-scheduler-component-testing)
6. [Integration Testing](#6-integration-testing)
7. [Performance Testing](#7-performance-testing)

## 1. DBT Component Testing

### Testing the Oracle Connection

```bash
# Access the DBT container
docker-compose exec dbt bash

# Run the debug command to test connection
dbt debug

# Expected output should show "Connection test: OK"
```

### Testing SQL Compilation

```bash
# Test compile without executing
dbt compile

# Check for compilation errors in the output
# Should show "Done" with no error messages
```

### Testing Individual Models

```bash
# Test the task_analytics model
dbt run --models task_analytics

# Test the exports model
dbt run --models exports_tasks_daily

# Verify the output files
exit  # Exit the container
ls -l data/exports/
```

### Validating Data Quality

```bash
# Access the DBT container again
docker-compose exec dbt bash

# Run data tests
dbt test

# Check CSV output (from within container)
head -n 5 /data/exports/tasks_daily.csv
```

## 2. Backend API Component Testing

### Basic API Health Check

```bash
# Check API health endpoint
curl http://localhost:8001/health

# Expected response: {"status":"healthy"}
```

### Testing Task Endpoints

```bash
# Get all tasks
curl http://localhost:8001/api/tasks

# Get tasks for a specific client
curl http://localhost:8001/api/tasks?client=GENZY

# Get tasks needing attention
curl http://localhost:8001/api/tasks/attention
```

### Testing Analytics Endpoints

```bash
# Get task statistics
curl http://localhost:8001/api/analytics/stats

# Get daily metrics
curl http://localhost:8001/api/analytics/daily

# Get client metrics
curl http://localhost:8001/api/analytics/clients
```

### Testing API Authentication (if implemented)

```bash
# Try accessing protected endpoint without token
curl http://localhost:8001/api/tasks

# Login to get token
TOKEN=$(curl -X POST http://localhost:8001/api/auth/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin&password=password" | jq -r '.access_token')

# Access protected endpoint with token
curl -H "Authorization: Bearer $TOKEN" http://localhost:8001/api/tasks
```

## 3. Ollama LLM Component Testing

### Testing Ollama Health

```bash
# Check if Ollama is running
curl http://localhost:11434/api/health

# List available models
docker-compose exec ollama ollama list
```

### Testing Model Generation

```bash
# Test basic generation with the model
curl -X POST http://localhost:11434/api/generate -d '{
  "model": "task-summarizer",
  "prompt": "Summarize this task: Need to review quarterly financial documents by end of week. Client is expecting feedback on revenue projections and cost analysis.",
  "stream": false
}'

# Expected: A concise summary of the task in 1-2 sentences
```

### Testing Model via Backend API

```bash
# If you've implemented a test endpoint for LLM:
curl -X POST http://localhost:8001/api/test/summarize \
  -H "Content-Type: application/json" \
  -d '{"content": "Need to review quarterly financial documents by end of week. Client is expecting feedback on revenue projections and cost analysis."}'

# Alternative: Test through a task detail endpoint if available
curl http://localhost:8001/api/tasks/1
```

## 4. Frontend Component Testing

### Basic Accessibility Testing

```bash
# Check if the frontend is accessible
curl -I http://localhost:3000

# Expected: HTTP/1.1 200 OK
```

### Browser Testing

Open http://localhost:3000 in your browser and verify:

- The dashboard loads without errors
- Navigation between tabs works (if implemented)
- Data is displayed correctly
- Client filtering works (if implemented)
- Task details can be viewed (if implemented)

### API Connection Testing

Use browser developer tools to:

1. Open Network tab
2. Reload the page
3. Look for API requests to the backend
4. Verify they return 200 status codes

## 5. Scheduler Component Testing

### Testing Cron Configuration

```bash
# Check if cron is running
docker-compose exec scheduler pgrep cron

# View crontab configuration
docker-compose exec scheduler crontab -l
```

### Manual Export Job Test

```bash
# Run the export job manually
docker-compose exec scheduler python /app/export_job.py

# Check for output in logs
docker-compose logs scheduler | tail -n 20

# Verify files were created/updated
ls -la data/exports/
```

### Verifying Backup Creation

```bash
# Check if timestamped backups exist
find data/exports -name "tasks_daily_*.csv"
```

## 6. Integration Testing

### End-to-End Data Flow Test

1. Modify data in Oracle (if possible):
   ```sql
   -- Example SQL to modify test data (run in Oracle)
   UPDATE your_task_table SET status = 'UPDATED' WHERE task_id = 123;
   ```

2. Run DBT models:
   ```bash
   docker-compose exec dbt dbt run
   ```

3. Verify data in the CSV:
   ```bash
   head -n 20 data/exports/tasks_daily.csv | grep 123
   ```

4. Check through API:
   ```bash
   curl http://localhost:8001/api/tasks | grep 123
   ```

5. Open frontend and verify the update appears

### LLM Integration Test

1. Create a task with specific content
2. View the task details through the API
3. Verify the summary is generated correctly

## 7. Performance Testing

### Database Query Performance

```bash
# Enter the DBT container
docker-compose exec dbt bash

# Run with profile flag to see query performance
dbt run --models task_analytics --profiles-dir=profiles --profile task_monitoring
```

### API Response Time Testing

```bash
# Install apache benchmark if needed
brew install apache2

# Perform a simple load test (10 requests, 2 concurrent)
ab -n 10 -c 2 http://localhost:8001/api/analytics/stats
```

### LLM Latency Testing

```bash
# Time the LLM response
time curl -X POST http://localhost:11434/api/generate -d '{
  "model": "task-summarizer", 
  "prompt": "Summarize this task: Need to review quarterly financial documents by end of week.", 
  "stream": false
}'
```

### Frontend Load Time Testing

```bash
# Use browser developer tools:
# 1. Open Performance tab
# 2. Record load time
# 3. Measure Time to Interactive (TTI)
```

## Conclusion

By completing these detailed component tests, you can be confident that your Task Monitoring System is functioning correctly. If any test fails, refer to the logs of the specific component for troubleshooting information.

For any persistent issues, check the Troubleshooting section of the Installation Guide or consult the Docker logs for more detailed information:

```bash
docker-compose logs [component_name]
```
