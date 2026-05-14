#!/bin/sh
set -e
if [ -f /usrapp/config/app.env ]; then
  export $(grep -v '^#' /usrapp/config/app.env | grep -v '^$' | xargs)
fi
mkdir -p /usrapp/log
cd /usrapp
exec uvicorn main:app \
  --host 0.0.0.0 \
  --port "${PORT:-8080}" \
  2>&1 | tee -a /usrapp/log/app.log
