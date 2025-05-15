#!/bin/bash
# start.sh - Backend startup script that ensures Ollama is ready before starting the application

# Check if LLM is enabled and provider is Ollama
if [ "${LLM_ENABLED,,}" = "true" ] && [ "${LLM_PROVIDER,,}" = "ollama" ]; then
    echo "LLM is enabled with Ollama provider. Setting up Ollama..."

    # Run the Ollama setup script
    /app/ollama-setup.sh

    # Check the return code
    if [ $? -ne 0 ]; then
        echo "Ollama setup failed. The application will continue, but LLM features may not work properly."
    else
        echo "Ollama setup completed successfully!"
    fi
else
    echo "Ollama setup skipped (LLM_ENABLED=$LLM_ENABLED, LLM_PROVIDER=$LLM_PROVIDER)"
fi

# Start the FastAPI application
echo "Starting the FastAPI application..."
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
