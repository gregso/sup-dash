# Docker Compose Quick Guide

Docker Compose makes it easy to manage multi-container applications. Here's how to handle the most common operations:

## Prerequisites

```bash
# Check if docker-compose is installed
docker-compose --version
```

## Starting Containers

```bash
# Start all services defined in docker-compose.yml
docker-compose up

# Run in detached (background) mode
docker-compose up -d

# Start only specific services
docker-compose up -d clickhouse oracle-sync
```

## Stopping Containers

```bash
# Stop all running containers
docker-compose down

# Stop but keep networks/volumes
docker-compose stop

# Stop specific services
docker-compose stop clickhouse
```

## Restarting Containers

```bash
# Restart all services
docker-compose restart

# Restart specific services
docker-compose restart oracle-sync
```

## Rebuilding Containers

```bash
# Rebuild all images and restart
docker-compose up -d --build

# Force-rebuild specific service
docker-compose build --no-cache oracle-sync
docker-compose up -d oracle-sync
```

## Useful Commands

```bash
# View logs
docker-compose logs

# Follow logs for specific service
docker-compose logs -f oracle-sync

# Check container status
docker-compose ps

# Execute command in running container
docker-compose exec oracle-sync python test_conn.py
```

## Handling Changes

- **Config changes**: Just restart the service
- **Code changes**: Rebuild the service with `--build`
- **Dockerfile changes**: Rebuild with `--no-cache`

Remember, the working directory should contain your `docker-compose.yml` file when running these commands.
