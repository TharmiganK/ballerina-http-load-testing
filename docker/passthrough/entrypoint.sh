#!/bin/bash

# Dynamic entrypoint for Ballerina Passthrough Service
# Configures service based on environment variables

# Default values (fallback to h1c-h1c if no configuration provided)
CLIENT_SSL=${CLIENT_SSL:-false}
SERVER_SSL=${SERVER_SSL:-false}
CLIENT_HTTP2=${CLIENT_HTTP2:-false}
SERVER_HTTP2=${SERVER_HTTP2:-false}
SERVER_PORT=${SERVER_PORT:-9094}
BACKEND_PORT=${BACKEND_PORT:-8701}
BACKEND_HOST=${BACKEND_HOST:-netty-backend}

# SSL certificate paths
EP_KEY_PATH=${EP_KEY_PATH:-./resources/ballerinaKeystore.p12}
EP_TRUST_STORE_PATH=${EP_TRUST_STORE_PATH:-./resources/ballerinaTruststore.p12}

# Log configuration being used
echo "[PASSTHROUGH] Starting Ballerina service with configuration:"
echo "  Server Port: $SERVER_PORT"
echo "  Backend: $BACKEND_HOST:$BACKEND_PORT"
echo "  Client SSL: $CLIENT_SSL"
echo "  Server SSL: $SERVER_SSL"
echo "  Client HTTP/2: $CLIENT_HTTP2"
echo "  Server HTTP/2: $SERVER_HTTP2"

# Build Java command with dynamic configuration
exec java \
    ${JAVA_OPTS} \
    -jar ballerina_passthrough.jar \
    -CepKeyPath="$EP_KEY_PATH" \
    -CepTrustStorePath="$EP_TRUST_STORE_PATH" \
    -CclientSsl="$CLIENT_SSL" \
    -CserverSsl="$SERVER_SSL" \
    -CclientHttp2="$CLIENT_HTTP2" \
    -CserverHttp2="$SERVER_HTTP2" \
    -CserverPort="$SERVER_PORT" \
    -CbackendPort="$BACKEND_PORT" \
    -CbackendHost="$BACKEND_HOST"