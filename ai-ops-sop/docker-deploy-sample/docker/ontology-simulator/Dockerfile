FROM python:3.11-slim
WORKDIR /usrapp

# Install dependencies
COPY ontology_simulator/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy application (exclude frontend — static export not needed inside container)
COPY ontology_simulator/main.py ./main.py
COPY ontology_simulator/config.py ./config.py
COPY ontology_simulator/app/ ./app/

# Run script
COPY deploy/docker/ontology-simulator/run.sh /usrapp/run.sh
RUN mkdir -p /usrapp/log /usrapp/config && \
    chmod +x /usrapp/run.sh

EXPOSE 8080
ENTRYPOINT ["/usrapp/run.sh"]
