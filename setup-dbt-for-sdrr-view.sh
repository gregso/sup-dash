#!/bin/bash
# setup-dbt-for-sdrr-view.sh - Script to set up the DBT models for SDRR_TASKACTIONS_CHAMPIONS view

# Create DBT project configuration file if it doesn't exist already
if [ ! -f dbt/dbt_project.yml ]; then
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
fi

# Create the schema file for the SDRR_TASKACTIONS_CHAMPIONS view
mkdir -p dbt/models
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

# Create the task analytics model
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

# Create the export models
cat > dbt/models/exports_tasks_daily.sql << 'EOF'
SELECT * FROM {{ ref('task_analytics') }}
EOF

# Create the macro directory and export_csv macro if it doesn't exist
mkdir -p dbt/macros
if [ ! -f dbt/macros/export_csv.sql ]; then
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
fi

echo "DBT models for SDRR_TASKACTIONS_CHAMPIONS view have been set up successfully!"
