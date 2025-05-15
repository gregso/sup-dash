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
