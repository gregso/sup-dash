#!/bin/bash
echo "oracle-sync waiting for ClickHouse..."

host="$1"
port="$2"
shift 2
cmd="$@"

until nc -z $host $port; do
  echo "Waiting for $host:$port..."
  sleep 1
done

echo "ClickHouse is up - executing command"
exec $cmd
