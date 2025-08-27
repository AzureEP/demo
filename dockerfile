# syntax=docker/dockerfile:1.7

# --- Build stage: compile Petclinic JAR with reproducible timestamp ---
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /src

# Copy dependency files first for better layer caching
COPY pom.xml ./
COPY src/main/resources/application*.properties src/main/resources/
RUN mvn -B -ntp dependency:go-offline

# Copy source code and build
COPY . .
ARG BUILD_TS
RUN mvn -B -ntp -Dproject.build.outputTimestamp=${BUILD_TS} -DskipTests clean package \
    && java -Djarmode=layertools -jar target/*.jar extract

# --- Runtime stage: minimal JRE, non-root ---
FROM eclipse-temurin:17-jre-jammy AS runtime

# Install security updates and remove package cache
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create non-root user with explicit UID/GID
RUN groupadd -g 10001 app \
    && useradd -u 10001 -g app -r -s /usr/sbin/nologin app \
    && mkdir -p /opt/app \
    && chown -R app:app /opt/app

WORKDIR /opt/app

# Copy Spring Boot layers for better caching (if using layertools)
COPY --from=build --chown=app:app /src/dependencies/ ./
COPY --from=build --chown=app:app /src/spring-boot-loader/ ./
COPY --from=build --chown=app:app /src/snapshot-dependencies/ ./
COPY --from=build --chown=app:app /src/application/ ./

# Fallback: copy JAR if not using layertools
# COPY --from=build --chown=app:app /src/target/*.jar app.jar

# Switch to non-root user
USER app

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

# Expose port
EXPOSE 8080

# Optimized JVM settings for containers
ENV JAVA_OPTS="-XX:+UseContainerSupport \
               -XX:MaxRAMPercentage=75 \
               -XX:+UseG1GC \
               -XX:+UseStringDeduplication \
               -Djava.security.egd=file:/dev/./urandom \
               -Dspring.profiles.active=docker"

# Use Spring Boot's layered JAR approach
ENTRYPOINT ["java", "-cp", "/opt/app", "org.springframework.boot.loader.JarLauncher"]

# Fallback entrypoint if not using layers
# ENTRYPOINT ["sh","-c","java $JAVA_OPTS -jar app.jar"]

# --- Metadata and traceability (OCI labels) ---
ARG BUILD_TS
ARG VCS_REF
ARG REPO_URL
ARG VERSION

LABEL org.opencontainers.image.created="${BUILD_TS}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.title="spring-petclinic" \
      org.opencontainers.image.description="Spring PetClinic sample application" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.vendor="Spring Community" \
      org.opencontainers.image.licenses="Apache-2.0" \
      maintainer="chirag.arora@india.nec.com"