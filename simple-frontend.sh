#!/bin/bash
# Create simple frontend

# Create a very simple Dockerfile for the frontend
cat > frontend/Dockerfile << 'EOF'
FROM nginx:alpine

# Create a simple HTML page
RUN echo '<html><body><h1>Task Monitoring Dashboard</h1><p>Placeholder for the real application.</p><div style="margin-top: 30px; padding: 20px; background-color: #f0f8ff; border-radius: 8px;"><h2>Features Coming Soon</h2><ul><li>Task overview and statistics</li><li>Live issue tracking</li><li>Department performance metrics</li><li>AI-powered task summarization</li></ul></div></body></html>' > /usr/share/nginx/html/index.html

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
EOF

# Create the nginx configuration
cat > frontend/nginx.conf << 'EOF'
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    # Handle React routing
    location / {
        try_files $uri $uri/ /index.html;
    }

    # API proxy
    location /api/ {
        proxy_pass http://backend:8000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

echo "Simple frontend files have been created. Try running 'docker-compose build' again."
