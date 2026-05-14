#!/bin/sh
set -e
if [ -f /usrapp/config/app.env ]; then
  export $(grep -v '^#' /usrapp/config/app.env | grep -v '^$' | xargs)
fi
mkdir -p /usrapp/log
exec java -server \
  -Xms256m -Xmx768m \
  -XX:+HeapDumpOnOutOfMemoryError \
  -XX:HeapDumpPath=/usrapp/log/heap-dump.hprof \
  -Duser.timezone=UTC \
  -Dfile.encoding=UTF-8 \
  -Dspring.profiles.active=prod \
  -Dspring.config.additional-location=file:/usrapp/config/ \
  -jar /usrapp/aiops-scheduler.jar
