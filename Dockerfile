FROM python:3.11-slim

WORKDIR /app

# Copy project files
COPY pyproject.toml README.md LICENSE ./
COPY src/ ./src/
COPY config/ ./config/

# Ensure the server can find tool package config without needing an env override
ENV TOOL_PACKAGE_CONFIG_PATH="/app/config/tool_packages.yaml"

# Install the package (non-editable) to avoid runtime build/metadata checks
RUN pip install --no-cache-dir .

# Expose the port the app runs on
EXPOSE 8080

# Command to run the application using the provided CLI
CMD ["servicenow-mcp-sse", "--host=0.0.0.0", "--port=8080"] 
