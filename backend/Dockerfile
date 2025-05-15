FROM python:3.9-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Add Ollama setup script
COPY ollama-setup.sh /app/ollama-setup.sh
RUN chmod +x /app/ollama-setup.sh

# Add startup script to check Ollama and then run the application
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Create the directory structure
RUN mkdir -p app/api/endpoints app/models app/services app/utils

# Expose the port the app runs on
EXPOSE 8000

# Run the startup script
CMD ["/app/start.sh"]
