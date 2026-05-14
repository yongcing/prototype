FROM python:3.11-slim
WORKDIR /usrapp

# Install dependencies
COPY python_ai_sidecar/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy application package
COPY python_ai_sidecar/ ./python_ai_sidecar/

# Run script
COPY deploy/docker/python-sidecar/run.sh /usrapp/run.sh
RUN mkdir -p /usrapp/log /usrapp/config && \
    chmod +x /usrapp/run.sh

EXPOSE 8080
ENTRYPOINT ["/usrapp/run.sh"]
