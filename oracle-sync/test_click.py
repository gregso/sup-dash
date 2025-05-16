import clickhouse_driver

client = clickhouse_driver.Client(
    host='clickhouse',
    user='default',
    password='default',
    database='support_analytics',
    settings={'use_numpy': False}
)

# Test with a very simple query
print("Tasks count: ", client.execute('SELECT count(*) FROM support_analytics.support_tasks'))

# Test with a simple table query
print(client.execute('SHOW TABLES'))
