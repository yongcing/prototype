# ── Stage 1: build ────────────────────────────────────────────────────────────
FROM eclipse-temurin:17-jdk-alpine AS builder
WORKDIR /build

COPY pom.xml ./
COPY java-backend/pom.xml ./java-backend/
COPY java-scheduler/pom.xml ./java-scheduler/
RUN apk add --no-cache maven && \
    mvn -B -ntp dependency:go-offline -pl java-scheduler -am

COPY java-backend/src ./java-backend/src
COPY java-scheduler/src ./java-scheduler/src
RUN mvn -B -ntp -Dmaven.test.skip=true clean package

# ── Stage 2: runtime ──────────────────────────────────────────────────────────
FROM eclipse-temurin:17-jre-alpine AS runner
WORKDIR /usrapp

COPY --from=builder /build/java-scheduler/target/aiops-scheduler.jar /usrapp/aiops-scheduler.jar
COPY deploy/docker/java-scheduler/config/application-docker.yml /usrapp/config/application-docker.yml
COPY deploy/docker/java-scheduler/run.sh /usrapp/run.sh

RUN mkdir -p /usrapp/log /usrapp/config && \
    chmod +x /usrapp/run.sh

EXPOSE 8080
ENTRYPOINT ["/usrapp/run.sh"]
