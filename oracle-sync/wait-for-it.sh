#!/bin/bash
# Use: ./wait-for-it.sh host:port [-- command args]

cmdname=$(basename $0)

# Show help
function show_help() {
    echo "Usage: $cmdname host:port [-s] [-t timeout] [-- command args]"
    echo "  -s               Silent mode, don't output anything"
    echo "  -t timeout       Timeout in seconds, zero for no timeout"
    echo "  -- command args  Execute command with args after the test finishes"
    exit 1
}

# Function to check if host:port is available
function wait_for() {
    if [[ $SILENT -eq 1 ]]; then
        timeout $TIMEOUT bash -c "until nc -z $HOST $PORT; do sleep 1; done" 2>/dev/null
    else
        echo "Waiting for $HOST:$PORT..."
        timeout $TIMEOUT bash -c "until nc -z $HOST $PORT; do echo -n '.'; sleep 1; done"
        echo
    fi

    RESULT=$?
    if [[ $RESULT -ne 0 ]]; then
        echo "Operation timed out" >&2
        exit 1
    fi

    if [[ $SILENT -ne 1 ]]; then
        echo "$HOST:$PORT is available after $WAITTIME second(s)"
    fi
    return $RESULT
}

WAITTIME=0
TIMEOUT=15
SILENT=0
COMMAND=""

# Process arguments
while [[ $# -gt 0 ]]
do
    case "$1" in
        *:*)
            hostport=(${1//:/ })
            HOST=${hostport[0]}
            PORT=${hostport[1]}
            shift 1
            ;;
        -s)
            SILENT=1
            shift 1
            ;;
        -t)
            TIMEOUT="$2"
            if [[ $TIMEOUT == "" ]]; then break; fi
            shift 2
            ;;
        --)
            shift
            COMMAND="$@"
            break
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown argument: $1"
            show_help
            ;;
    esac
done

if [[ $HOST == "" || $PORT == "" ]]; then
    show_help
fi

# Install netcat if it's not there
apt-get update && apt-get install -y netcat > /dev/null

# Wait for service to be ready
wait_for

# Execute additional command if provided
if [[ $COMMAND != "" ]]; then
    if [[ $SILENT -ne 1 ]]; then
        echo "Executing command: $COMMAND"
    fi
    exec $COMMAND
fi
