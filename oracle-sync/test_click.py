import clickhouse_driver

client = clickhouse_driver.Client(
    host='clickhouse',
    user='default',
    password='default',
    database='support_analytics',
    settings={'use_numpy': False}
)

# Test with a very simple query
print(client.execute('SELECT 1'))

# Test with a simple table query
print(client.execute('SHOW TABLES'))
