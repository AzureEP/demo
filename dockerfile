# syntax=docker/dockerfile:1.7

# --- Build stage: compile Petclinic JAR with reproducible timestamp ---
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /src
COPY . .
ARG BUILD_TS
RUN mvn -B -ntp -Dproject.build.outputTimestamp=${BUILD_TS} -DskipTests package

# --- Runtime stage: minimal JRE, non-root ---
FROM eclipse-temurin:17-jre-jammy
RUN useradd -u 10001 -r -s /usr/sbin/nologin app \
 && mkdir -p /opt/app \
 && chown -R app:app /opt/app
WORKDIR /opt/app
COPY --from=build /src/target/*.jar app.jar

USER app
EXPOSE 8080
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75"
ENTRYPOINT ["sh","-c","java $JAVA_OPTS -jar app.jar"]

# --- Traceability (OCI labels) ---
ARG BUILD_TS
ARG VCS_REF
ARG REPO_URL
LABEL org.opencontainers.image.created="${BUILD_TS}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.title="spring-petclinic"
