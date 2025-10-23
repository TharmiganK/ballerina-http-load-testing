#!/bin/bash

# Dynamic entrypoint for Netty Backend Service
# Configures service based on environment variables

# Default values (fallback to h1c-h1c backend configuration)
BACKEND_PORT=${BACKEND_PORT:-8701}
SSL_ENABLED=${SSL_ENABLED:-false}
HTTP2_ENABLED=${HTTP2_ENABLED:-false}
SLEEP_TIME=${SLEEP_TIME:-0}

# Log configuration being used
echo "[BACKEND] Starting Netty service with configuration:"
echo "  Port: $BACKEND_PORT"
echo "  SSL Enabled: $SSL_ENABLED"
echo "  HTTP/2 Enabled: $HTTP2_ENABLED"
echo "  Sleep Time: ${SLEEP_TIME}ms"

# Build Java command with dynamic configuration
JAVA_ARGS=(
    ${JAVA_OPTS}
    -jar netty-http-echo-service.jar
    --port "$BACKEND_PORT"
)

# Add SSL configuration if enabled
if [ "$SSL_ENABLED" = "true" ]; then
    JAVA_ARGS+=(--ssl "true")
fi

# Add HTTP/2 configuration if enabled
if [ "$HTTP2_ENABLED" = "true" ]; then
    JAVA_ARGS+=(--http2 "true")
fi

# Add sleep time if specified
if [ "$SLEEP_TIME" != "0" ]; then
    JAVA_ARGS+=(--sleep "$SLEEP_TIME")
fi

# Execute the Java application
echo "Executing command: java ${JAVA_ARGS[@]}"
exec java "${JAVA_ARGS[@]}"