FROM nginx:alpine

# Create a simple HTML page
RUN echo '<html><body><h1>Task Monitoring Dashboard</h1><p>Placeholder for the real application.</p><div style="margin-top: 30px; padding: 20px; background-color: #f0f8ff; border-radius: 8px;"><h2>Features Coming Soon</h2><ul><li>Task overview and statistics</li><li>Live issue tracking</li><li>Department performance metrics</li><li>AI-powered task summarization</li></ul></div></body></html>' > /usr/share/nginx/html/index.html

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
