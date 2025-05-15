# Check what process is using port 8000
if command -v lsof >/dev/null 2>&1; then
    PORT_INFO=$(lsof -i :8000 -P -n)
    if [ -n "$PORT_INFO" ]; then
        echo "Port 8000 is currently in use by:"
        echo "$PORT_INFO"

        # Get the PID of the process using port 8000
        PID=$(echo "$PORT_INFO" | grep -v "PID" | awk '{print $2}' | head -n 1)
        if [ -n "$PID" ]; then
            read -p "Do you want to kill the process (PID: $PID) using port 8000? (y/n) " KILL_PROCESS
            if [[ $KILL_PROCESS == "y" || $KILL_PROCESS == "Y" ]]; then
                echo "Killing process with PID: $PID"
                kill -9 $PID
                echo "Process killed. You can try starting your Docker containers again."
                exit 0
            fi
        fi
    else
        echo "No process found using port 8000 directly. It might be used by a Docker container."

        # Check if Docker containers are using the port
        DOCKER_CONTAINER=$(docker ps | grep -E "0.0.0.0:8000|:::8000" || true)
        if [ -n "$DOCKER_CONTAINER" ]; then
            echo "Docker container is using port 8000:"
            echo "$DOCKER_CONTAINER"

            # Get the container ID
            CONTAINER_ID=$(echo "$DOCKER_CONTAINER" | awk '{print $1}')
            if [ -n "$CONTAINER_ID" ]; then
                read -p "Do you want to stop this Docker container? (y/n) " STOP_CONTAINER
                if [[ $STOP_CONTAINER == "y" || $STOP_CONTAINER == "Y" ]]; then
                    echo "Stopping Docker container: $CONTAINER_ID"
                    docker stop $CONTAINER_ID
                    echo "Container stopped. You can try starting your Docker containers again."
                    exit 0
                fi
            fi
        else
            echo "No Docker container found using port 8000."
        fi
    fi
else
    echo "lsof command not found. Unable to check which process is using port 8000."
fi

# Offer to change the port in docker-compose.yml
echo ""
echo "Alternative solution: Change the backend port in docker-compose.yml"
read -p "Do you want to change the backend port from 8000 to 8001? (y/n) " CHANGE_PORT

if [[ $CHANGE_PORT == "y" || $CHANGE_PORT == "Y" ]]; then
    # Create a backup of the original docker-compose.yml
    cp docker-compose.yml docker-compose.yml.bak

    # Replace port 8000 with 8001 for the backend service
    sed -i '' 's/- "8000:8000"/- "8001:8000"/' docker-compose.yml 2>/dev/null || sed -i 's/- "8000:8000"/- "8001:8000"/' docker-compose.yml

    # Also update the CORS_ORIGINS if it contains localhost:8000
    sed -i '' 's/http:\/\/localhost:8000/http:\/\/localhost:8001/g' docker-compose.yml 2>/dev/null || sed -i 's/http:\/\/localhost:8000/http:\/\/localhost:8001/g' docker-compose.yml

    # If API_URL is set to localhost:8000 in .env, update it
    if grep -q "API_URL.*localhost:8000" .env 2>/dev/null; then
        sed -i '' 's/localhost:8000/localhost:8001/g' .env 2>/dev/null || sed -i 's/localhost:8000/localhost:8001/g' .env
    fi

    echo "Port has been changed from 8000 to 8001 in docker-compose.yml"
    echo "A backup of the original file has been saved as docker-compose.yml.bak"
    echo "Your backend will now be available at http://localhost:8001 instead of http://localhost:8000"
    echo "You can now try starting your Docker containers again with: docker-compose up -d"
else
    echo "No changes made. Please free up port 8000 before starting the Docker containers."
fi
