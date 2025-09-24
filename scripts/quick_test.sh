#!/bin/bash

# Quick test script for individual service testing using unified Ballerina project
# Usage: ./quick_test.sh <service> <file_size> <users> <duration>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="${PROJECT_ROOT}/quick_results"
BALLERINA_PROJECT_DIR="${PROJECT_ROOT}/ballerina-passthrough"
NETTY_BACKEND_DIR="${PROJECT_ROOT}/netty-backend"
NETTY_JAR="${NETTY_BACKEND_DIR}/netty-http-echo-service.jar"
BALLERINA_JAR="${BALLERINA_PROJECT_DIR}/target/bin/ballerina_passthrough.jar"

# Service configurations - using regular arrays
SERVICE_NAMES=("h1-h1" "h1c-h1" "h1-h1c" "h1c-h1c")
SERVICE_PORTS=(9091 9092 9093 9094)
SERVICE_PROTOCOLS=("https" "http" "https" "http")
SERVICE_CLIENT_SSL=(true true false false)
SERVICE_SERVER_SSL=(true false true false)
SERVICE_BACKEND_SSL=(true true false false)
SERVICE_BACKEND_PORTS=(8689 8689 8688 8688)

# Helper functions to get service properties
get_service_port() {
    local service=$1
    for i in "${!SERVICE_NAMES[@]}"; do
        if [ "${SERVICE_NAMES[$i]}" = "$service" ]; then
            echo "${SERVICE_PORTS[$i]}"
            return
        fi
    done
}

get_service_protocol() {
    local service=$1
    for i in "${!SERVICE_NAMES[@]}"; do
        if [ "${SERVICE_NAMES[$i]}" = "$service" ]; then
            echo "${SERVICE_PROTOCOLS[$i]}"
            return
        fi
    done
}

get_service_client_ssl() {
    local service=$1
    for i in "${!SERVICE_NAMES[@]}"; do
        if [ "${SERVICE_NAMES[$i]}" = "$service" ]; then
            echo "${SERVICE_CLIENT_SSL[$i]}"
            return
        fi
    done
}

get_service_server_ssl() {
    local service=$1
    for i in "${!SERVICE_NAMES[@]}"; do
        if [ "${SERVICE_NAMES[$i]}" = "$service" ]; then
            echo "${SERVICE_SERVER_SSL[$i]}"
            return
        fi
    done
}

get_service_backend_ssl() {
    local service=$1
    for i in "${!SERVICE_NAMES[@]}"; do
        if [ "${SERVICE_NAMES[$i]}" = "$service" ]; then
            echo "${SERVICE_BACKEND_SSL[$i]}"
            return
        fi
    done
}

get_service_backend_port() {
    local service=$1
    for i in "${!SERVICE_NAMES[@]}"; do
        if [ "${SERVICE_NAMES[$i]}" = "$service" ]; then
            echo "${SERVICE_BACKEND_PORTS[$i]}"
            return
        fi
    done
}

# Default parameters
SERVICE=${1:-"h1c-h1c"}
FILE_SIZE=${2:-"1KB"}
USERS=${3:-"100"}
DURATION=${4:-"60"}

PORT=$(get_service_port "$SERVICE")
PROTOCOL=$(get_service_protocol "$SERVICE")
CLIENT_SSL=$(get_service_client_ssl "$SERVICE")
SERVER_SSL=$(get_service_server_ssl "$SERVICE")
BACKEND_SSL=$(get_service_backend_ssl "$SERVICE")
BACKEND_PORT=$(get_service_backend_port "$SERVICE")

if [ -z "$PORT" ]; then
    echo "Error: Invalid service '$SERVICE'"
    echo "Valid services: ${SERVICE_NAMES[*]}"
    exit 1
fi

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    pkill -f "ballerina_passthrough.jar" 2>/dev/null || true
    pkill -f "netty-http-echo-service.jar" 2>/dev/null || true
}

trap cleanup EXIT

echo "Quick testing: $SERVICE ($PROTOCOL://localhost:$PORT)"
echo "Parameters: File=$FILE_SIZE, Users=$USERS, Duration=${DURATION}s"
echo "Backend: $([ "$BACKEND_SSL" = "true" ] && echo "HTTPS" || echo "HTTP") on port $BACKEND_PORT"

# Check if JMeter is available
if ! command -v jmeter &> /dev/null; then
    echo "Error: JMeter is not installed"
    exit 1
fi

# Check if JAR files exist
if [ ! -f "$BALLERINA_JAR" ]; then
    echo "Error: Ballerina JAR not found: $BALLERINA_JAR"
    echo "Please build first with: cd ballerina-passthrough && bal clean && bal build"
    exit 1
fi

if [ ! -f "$NETTY_JAR" ]; then
    echo "Error: Netty JAR not found: $NETTY_JAR"
    exit 1
fi

# Create results directory
mkdir -p "$RESULTS_DIR"

# Start netty backend
echo "Starting netty backend..."
cd "$NETTY_BACKEND_DIR"
if [ "$BACKEND_SSL" = "true" ]; then
    nohup java -jar "$NETTY_JAR" --ssl true --http2 false --key-store-file "${PROJECT_ROOT}/resources/ballerinaKeystore.p12" --key-store-password ballerina > "$RESULTS_DIR/netty_backend.log" 2>&1 &
else
    nohup java -jar "$NETTY_JAR" --ssl false --http2 false > "$RESULTS_DIR/netty_backend.log" 2>&1 &
fi
BACKEND_PID=$!
echo "Backend started with PID: $BACKEND_PID"

# Wait for backend to start
sleep 5

# Check if backend is running
if ! lsof -Pi :$BACKEND_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "Error: Backend failed to start on port $BACKEND_PORT"
    exit 1
fi

# Start Ballerina service
echo "Starting Ballerina service..."
cd "$BALLERINA_PROJECT_DIR"
nohup java -jar "$BALLERINA_JAR" \
    -CclientSsl="$CLIENT_SSL" \
    -CserverSsl="$SERVER_SSL" \
    -CserverPort="$PORT" \
    > "$RESULTS_DIR/${SERVICE}.log" 2>&1 &
SERVICE_PID=$!
echo "Service started with PID: $SERVICE_PID"

# Wait for service to start
sleep 10

# Check if service is running
if ! lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "Error: Service failed to start on port $PORT"
    exit 1
fi

echo "Both backend and service are running. Starting load test..."

# Run the test
jmeter -n -t "${PROJECT_ROOT}/passthrough-test-simple.jmx" \
    -Jthreads=$USERS \
    -Jrampup=10 \
    -Jduration=$DURATION \
    -Jfilesize=$FILE_SIZE \
    -Jhost=localhost \
    -Jport=$PORT \
    -Jprotocol=$PROTOCOL \
    -Jservicetype=$SERVICE \
    -l "${RESULTS_DIR}/quick_test_${SERVICE}_${FILE_SIZE}_${USERS}users.jtl" \
    -j "${RESULTS_DIR}/quick_test.log"

echo "Quick test completed!"
echo "Results saved to: ${RESULTS_DIR}/"
echo "Service log: ${RESULTS_DIR}/${SERVICE}.log"
echo "Backend log: ${RESULTS_DIR}/netty_backend.log"