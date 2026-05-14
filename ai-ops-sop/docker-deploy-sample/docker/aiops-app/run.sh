#!/bin/sh
set -e
if [ -f /usrapp/config/.env ]; then
  export $(grep -v '^#' /usrapp/config/.env | grep -v '^$' | xargs)
fi
mkdir -p /usrapp/log
exec node /usrapp/server.js 2>&1 | tee -a /usrapp/log/app.log
