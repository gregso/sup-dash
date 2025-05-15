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
      driver_type: thin
      protocol: tcp
      database: "${DBT_ORACLE_SERVICE}"
      username: "${DBT_ORACLE_USER}"
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
