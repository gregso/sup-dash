#!/bin/bash
# ollama-setup.sh - Script to setup Ollama models and perform initial configuration

# Ensure Ollama service is available
echo "Waiting for Ollama service to be ready..."
timeout=60
counter=0
while ! curl -s --head -f http://ollama:11434/api/health >/dev/null 2>&1; do
    if [ $counter -ge $timeout ]; then
        echo "Timed out waiting for Ollama to be ready"
        exit 1
    fi
    echo "Waiting for Ollama service... ($counter/$timeout)"
    sleep 1
    counter=$((counter+1))
done

echo "Ollama service is ready!"

# Check if specified model exists
MODEL=${OLLAMA_MODEL:-llama3}
echo "Checking if model $MODEL is available..."

if ! curl -s "http://ollama:11434/api/tags" | grep -q "\"name\":\"$MODEL\""; then
    echo "Model $MODEL not found. Pulling model..."

    # Pull the model
    curl -X POST http://ollama:11434/api/pull -d "{\"name\":\"$MODEL\"}"

    # Check if pull was successful
    if ! curl -s "http://ollama:11434/api/tags" | grep -q "\"name\":\"$MODEL\""; then
        echo "Failed to pull model $MODEL. Please check Ollama logs."
        echo "Available models:"
        curl -s "http://ollama:11434/api/tags" | jq -r '.models[].name'
        exit 1
    fi

    echo "Model $MODEL pulled successfully"
else
    echo "Model $MODEL is already available"
fi

# Create optimized task summarizer model
echo "Creating optimized task summarizer model..."

# Create Modelfile
cat > /tmp/Modelfile << EOL
FROM $MODEL
SYSTEM You are a task summarization assistant. Always provide concise, factual summaries focusing on key actions and deadlines. Limit your response to 1-2 sentences.
PARAMETER temperature 0.3
PARAMETER num_predict 100
EOL

# Create the model
curl -X POST http://ollama:11434/api/create -d "{
  \"name\": \"task-summarizer\",
  \"modelfile\": \"$(cat /tmp/Modelfile | base64 | tr -d '\n')\"
}"

echo "Task summarizer model created successfully"

# Display available models
echo "Available models:"
curl -s "http://ollama:11434/api/tags" | jq -r '.models[].name'

echo "Ollama setup completed successfully!"
