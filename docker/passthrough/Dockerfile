# Dockerfile for Ballerina Passthrough Service
FROM eclipse-temurin:21-jre

# Set working directory
WORKDIR /app

# Copy the built JAR file
COPY ballerina-passthrough/target/bin/ballerina_passthrough.jar .

# Copy keystore files
COPY resources/ballerinaKeystore.p12 ./resources/
COPY resources/ballerinaTruststore.p12 ./resources/

# Expose all service ports
EXPOSE 9091-9106

# Create entrypoint script for dynamic configuration
COPY docker/passthrough/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Use entrypoint script for dynamic service configuration
ENTRYPOINT ["/entrypoint.sh"]