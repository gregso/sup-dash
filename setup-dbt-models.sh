#!/bin/bash
# setup-dbt-models.sh - Script to set up the DBT models

# Create DBT project configuration file
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

# Create the schema file
mkdir -p dbt/models
cat > dbt/models/schema.yml << 'EOF'
version: 2

sources:
  - name: oracle
    database: "{{ env_var('DBT_ORACLE_SERVICE') }}"
    schema: "{{ env_var('DBT_ORACLE_SCHEMA') }}"
    tables:
      - name: raw_tasks
        description: "Raw tasks data from Oracle"
        columns:
          - name: TASK_ID
            description: "Unique identifier for the task"
          - name: CLIENT
            description: "Client associated with the task"
          - name: LIVEISSUE
            description: "Flag indicating if task is a live issue (Y/N)"
          - name: CREATEDDATETIME
            description: "When the task was created"
          - name: DEPT_DESCR
            description: "Department handling the task"
          - name: DIV_DESCR
            description: "Division handling the task"
          - name: ASSIGNEDTO
            description: "Employee assigned to the task"
          - name: JOB_CLASSIFICATION
            description: "Job classification"
          - name: STATUS12
            description: "Status of the task"

      - name: raw_actions
        description: "Raw actions data from Oracle"
        columns:
          - name: TASK_ID
            description: "Task ID linking to tasks table"
          - name: CLIENT
            description: "Client associated with the task"
          - name: ACTDATETIME
            description: "When the action was performed"
          - name: ACTIONCODE12
            description: "Code representing the action type"
          - name: ACTEMPL
            description: "Employee who performed the action"

      - name: task_content
        description: "Content data for tasks"
        columns:
          - name: TASK_ID
            description: "Task ID linking to tasks table"
          - name: CONTENT
            description: "Content of the task for LLM summarization"

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

  - name: task_content
    description: "Task content information for LLM processing"
    columns:
      - name: task_id
        description: "Unique identifier for the task"
        tests:
          - not_null
      - name: client
        description: "Client associated with the task"
      - name: task_content
        description: "Content of the task for LLM summarization"

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

  - name: exports_content_daily
    description: "Daily CSV export of task content data"
    config:
      post-hook:
        - "{{ export_csv('exports_content_daily', '/data/exports/task_content_daily.csv') }}"
    columns:
      - name: task_id
        description: "Unique identifier for the task"
      - name: client
        description: "Client associated with the task"
      - name: task_content
        description: "Content of the task for LLM summarization"
EOF

# Create the task analytics model
cat > dbt/models/task_analytics.sql << 'EOF'
WITH latest_actions AS (
    SELECT
        TASK_ID,
        CLIENT,
        MAX(ACTDATETIME) as last_action_datetime
    FROM
        {{ source('oracle', 'raw_actions') }}
    GROUP BY
        TASK_ID, CLIENT
),

task_actions AS (
    SELECT
        t.TASK_ID,
        t.CLIENT,
        t.LIVEISSUE as live_issue,
        t.CREATEDDATETIME as created_datetime,
        la.last_action_datetime,
        a.ACTIONCODE12 as last_action_code,
        a.ACTEMPL as last_action_employee,
        t.DEPT_DESCR as department,
        t.ASSIGNEDTO as assigned_to,
        t.DIV_DESCR as division,
        t.JOB_CLASSIFICATION as job_classification,
        t.STATUS12 as status
    FROM
        {{ source('oracle', 'raw_tasks') }} t
    JOIN
        latest_actions la ON t.TASK_ID = la.TASK_ID AND t.CLIENT = la.CLIENT
    LEFT JOIN
        {{ source('oracle', 'raw_actions') }} a ON t.TASK_ID = a.TASK_ID
            AND t.CLIENT = a.CLIENT
            AND la.last_action_datetime = a.ACTDATETIME
)

SELECT
    TASK_ID as task_id,
    CLIENT as client,
    live_issue,
    created_datetime,
    last_action_datetime,
    last_action_code,
    last_action_employee,
    department,
    assigned_to,
    division,
    job_classification,
    status,
    DATEDIFF('day', last_action_datetime, CURRENT_TIMESTAMP()) as days_since_last_action
FROM
    task_actions
EOF

# Create the task content model
cat > dbt/models/task_content.sql << 'EOF'
SELECT
    t.TASK_ID as task_id,
    t.CLIENT as client,
    tc.CONTENT as task_content
FROM
    {{ source('oracle', 'raw_tasks') }} t
LEFT JOIN
    {{ source('oracle', 'task_content') }} tc ON t.TASK_ID = tc.TASK_ID
WHERE
    tc.CONTENT IS NOT NULL
EOF

# Create the export models
cat > dbt/models/exports_tasks_daily.sql << 'EOF'
SELECT * FROM {{ ref('task_analytics') }}
EOF

cat > dbt/models/exports_content_daily.sql << 'EOF'
SELECT * FROM {{ ref('task_content') }}
EOF

# Create the macro directory and export_csv macro
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

# Create a sample profiles.yml to guide setup
mkdir -p dbt/profiles
cat > dbt/profiles/profiles.yml.example << 'EOF'
task_monitoring:
  outputs:
    dev:
      type: oracle
      user: "{{ env_var('DBT_ORACLE_USER') }}"
      password: "{{ env_var('DBT_ORACLE_PASSWORD') }}"
      host: "{{ env_var('DBT_ORACLE_HOST') }}"
      port: "{{ env_var('DBT_ORACLE_PORT') | as_number }}"
      service: "{{ env_var('DBT_ORACLE_SERVICE') }}"
      schema: "{{ env_var('DBT_ORACLE_SCHEMA') }}"
      threads: 4
    prod:
      type: oracle
      user: "{{ env_var('DBT_ORACLE_USER') }}"
      password: "{{ env_var('DBT_ORACLE_PASSWORD') }}"
      host: "{{ env_var('DBT_ORACLE_HOST') }}"
      port: "{{ env_var('DBT_ORACLE_PORT') | as_number }}"
      service: "{{ env_var('DBT_ORACLE_SERVICE') }}"
      schema: "{{ env_var('DBT_ORACLE_SCHEMA') }}"
      threads: 8
  target: dev
EOF

echo "DBT models have been set up successfully!"
echo "Note: You need to copy the profiles.yml.example to ~/.dbt/profiles.yml on your development machine"
