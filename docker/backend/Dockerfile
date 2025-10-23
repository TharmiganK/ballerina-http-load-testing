# Dockerfile for Netty Backend Service  
# Dockerfile for Netty Backend Service  
FROM eclipse-temurin:21-jre

# Set working directory
WORKDIR /app

# Copy the built JAR file
COPY netty-backend/target/netty-http-echo-service.jar .

# Copy keystore files
COPY resources/ballerinaKeystore.p12 ./resources/
COPY resources/ballerinaTruststore.p12 ./resources/

# Expose all backend ports
EXPOSE 8688-8709

# Create entrypoint script for dynamic configuration
COPY docker/backend/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Use entrypoint script for dynamic service configuration
ENTRYPOINT ["/entrypoint.sh"]