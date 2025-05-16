CREATE DATABASE IF NOT EXISTS support_analytics;

-- Create a table based on the Oracle view structure
CREATE TABLE IF NOT EXISTS support_analytics.support_tasks (
    act_aa_id String,
    task_id String,
    client String,
    status12 String,
    createddatetime DateTime,
    group String,
    company String,
    position String,
    job_classification String,
    email String,
    dept_descr String,
    div_descr String,
    liveissue String,
    task_class String,
    pr_ac_sort Int32,
    viewyn String,
    actdatetime DateTime,
    actioncode12 String,
    actempl String,
    assignedto String,
    task_aa_id String,
    product String,

    -- Metadata fields for tracking
    _sync_time DateTime DEFAULT now(),
    _row_id String MATERIALIZED act_aa_id
)
ENGINE = MergeTree()
ORDER BY (actdatetime, act_aa_id)
PARTITION BY toYYYYMM(actdatetime);

-- Create a view for performance analytics
CREATE VIEW IF NOT EXISTS support_analytics.task_performance AS
SELECT
    task_id,
    client,
    status12 AS status,
    dept_descr AS department,
    div_descr AS division,
    job_classification,
    liveissue,
    task_class,
    product,
    createddatetime AS created_at,
    actdatetime AS action_at,
    dateDiff('minute', createddatetime, actdatetime) AS response_time_minutes,
    dateDiff('hour', createddatetime, actdatetime) AS response_time_hours,
    dateDiff('day', createddatetime, actdatetime) AS response_time_days
FROM support_analytics.support_tasks;
