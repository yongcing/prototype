# ── Stage 1: build ────────────────────────────────────────────────────────────
FROM eclipse-temurin:17-jdk-alpine AS builder
WORKDIR /build

# Copy pom files first for layer caching
COPY pom.xml ./
COPY java-backend/pom.xml ./java-backend/
COPY java-scheduler/pom.xml ./java-scheduler/
RUN apk add --no-cache maven && \
    mvn -B -ntp dependency:go-offline -pl java-backend -am

# Copy source and build
COPY java-backend/src ./java-backend/src
COPY java-scheduler/src ./java-scheduler/src
RUN mvn -B -ntp -Dmaven.test.skip=true clean package

# ── Stage 2: runtime ──────────────────────────────────────────────────────────
FROM eclipse-temurin:17-jre-alpine AS runner
WORKDIR /usrapp

COPY --from=builder /build/java-backend/target/aiops-api.jar /usrapp/aiops-api.jar
COPY deploy/docker/java-backend/config/application-docker.yml /usrapp/config/application-docker.yml
COPY deploy/docker/java-backend/run.sh /usrapp/run.sh

RUN mkdir -p /usrapp/log /usrapp/config && \
    chmod +x /usrapp/run.sh

EXPOSE 8080
ENTRYPOINT ["/usrapp/run.sh"]
