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
