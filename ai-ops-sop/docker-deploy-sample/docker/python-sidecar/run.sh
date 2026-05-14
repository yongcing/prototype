#!/bin/sh
set -e
if [ -f /usrapp/config/app.env ]; then
  export $(grep -v '^#' /usrapp/config/app.env | grep -v '^$' | xargs)
fi
mkdir -p /usrapp/log
cd /usrapp
exec uvicorn python_ai_sidecar.main:app \
  --host 0.0.0.0 \
  --port "${SIDECAR_PORT:-8080}" \
  --workers 1 \
  2>&1 | tee -a /usrapp/log/app.log
