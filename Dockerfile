# Use multi-stage build for better caching and smaller image size
FROM eclipse-temurin:21-jdk-alpine AS builder

# Set working directory
WORKDIR /app

# Copy gradle wrapper and build files first for better layer caching
COPY springboot-backend/gradlew springboot-backend/gradlew
COPY springboot-backend/gradle springboot-backend/gradle
COPY springboot-backend/build.gradle springboot-backend/build.gradle
COPY springboot-backend/settings.gradle springboot-backend/settings.gradle

# Download dependencies
RUN cd springboot-backend && ./gradlew dependencies --no-daemon

# Copy source code
COPY springboot-backend/src springboot-backend/src

# Build the application
RUN cd springboot-backend && ./gradlew bootJar -x test --no-daemon

# Runtime stage
FROM eclipse-temurin:21-jre-alpine

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init

# Create app user for security
RUN addgroup -g 1001 appgroup && adduser -u 1001 -G appgroup -s /bin/sh -D appuser

# Set working directory
WORKDIR /app

# Copy the built JAR from builder stage
COPY --from=builder /app/springboot-backend/build/libs/*.jar app.jar

# Change ownership to app user
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1

# Run the application with dumb-init
ENTRYPOINT ["dumb-init", "--"]
CMD ["java", "-jar", "app.jar"]
