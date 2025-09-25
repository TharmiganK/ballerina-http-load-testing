#!/bin/bash

# Quick test script for individual service testing using unified Ballerina project
# Usage: ./quick_test.sh <service> <file_size> <users> <duration>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="${PROJECT_ROOT}/quick_results"
BALLERINA_PROJECT_DIR="${PROJECT_ROOT}/ballerina-passthrough"
NETTY_BACKEND_DIR="${PROJECT_ROOT}/netty-backend"
NETTY_JAR="${NETTY_BACKEND_DIR}/target/netty-http-echo-service.jar"
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

# Check if h2load is available
if ! command -v h2load &> /dev/null; then
    echo "Error: h2load is not installed"
    echo "Install with: sudo apt-get install nghttp2-client (Ubuntu/Debian)"
    echo "            or brew install nghttp2 (macOS)"
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
    echo "Please build first with: cd netty-backend && mvn clean package -DskipTests"
    exit 1
fi

# Create results directory
mkdir -p "$RESULTS_DIR"

# Start netty backend
echo "Starting netty backend..."
cd "$NETTY_BACKEND_DIR"
if [ "$BACKEND_SSL" = "true" ]; then
    nohup java -jar "$NETTY_JAR" --port $BACKEND_PORT --ssl true --http2 false --key-store-file "${PROJECT_ROOT}/resources/ballerinaKeystore.p12" --key-store-password ballerina > "$RESULTS_DIR/netty_backend.log" 2>&1 &
else
    nohup java -jar "$NETTY_JAR" --port $BACKEND_PORT --ssl false --http2 false > "$RESULTS_DIR/netty_backend.log" 2>&1 &
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

# Prepare data file based on payload size
DATA_FILE="${RESULTS_DIR}/test_payload_${FILE_SIZE}.txt"
if [ -f "${PROJECT_ROOT}/samples/${FILE_SIZE}.txt" ]; then
    cp "${PROJECT_ROOT}/samples/${FILE_SIZE}.txt" "$DATA_FILE"
else
    echo "Warning: Sample file not found, creating placeholder data"
    case "$FILE_SIZE" in
        "1KB") dd if=/dev/zero bs=1024 count=1 | tr '\0' 'A' > "$DATA_FILE" 2>/dev/null ;;
        "5KB") dd if=/dev/zero bs=1024 count=5 | tr '\0' 'A' > "$DATA_FILE" 2>/dev/null ;;
        "10KB") dd if=/dev/zero bs=1024 count=10 | tr '\0' 'A' > "$DATA_FILE" 2>/dev/null ;;
        "100KB") dd if=/dev/zero bs=1024 count=100 | tr '\0' 'A' > "$DATA_FILE" 2>/dev/null ;;
        "500KB") dd if=/dev/zero bs=1024 count=500 | tr '\0' 'A' > "$DATA_FILE" 2>/dev/null ;;
        "1MB") dd if=/dev/zero bs=1024 count=1024 | tr '\0' 'A' > "$DATA_FILE" 2>/dev/null ;;
        *) echo "Creating 1KB default payload"; echo "A" > "$DATA_FILE" ;;
    esac
fi

# Build h2load URL
BASE_URL="${PROTOCOL}://localhost:${PORT}"
TEST_URL="${BASE_URL}/passthrough"

# Run h2load test with appropriate options
echo "Running h2load test..."
echo "URL: $TEST_URL"
echo "Clients: $USERS, Duration: ${DURATION}s"

# h2load command with output redirection
h2load_output="${RESULTS_DIR}/h2load_raw_${SERVICE}_${FILE_SIZE}_${USERS}users.txt"
csv_output="${RESULTS_DIR}/quick_test_${SERVICE}_${FILE_SIZE}_${USERS}users.csv"

# Run h2load with the data file as POST body (show output in terminal and save to file)
if [ "$PROTOCOL" = "https" ]; then
    # For HTTPS
    h2load -c "$USERS" -t 1 -D "$DURATION" -d "$DATA_FILE" \
        --h1 "$TEST_URL" 2>&1 | tee "$h2load_output"
else
    # For HTTP
    h2load -c "$USERS" -t 1 -D "$DURATION" -d "$DATA_FILE" \
        --h1 "$TEST_URL" 2>&1 | tee "$h2load_output"
fi

# Parse h2load output to create simplified CSV report
echo "test_type,total_requests,duration_sec,throughput_rps,avg_latency_ms,error_rate_percent" > "$csv_output"

# Extract key metrics from h2load output
if [ -f "$h2load_output" ]; then
    # Parse h2load output for metrics
    total_requests=$(grep "requests:" "$h2load_output" | awk '{print $2}' || echo "0")
    successful_requests=$(grep "status codes:" "$h2load_output" | awk '{print $3}' || echo "0")
    failed_requests=$((total_requests - successful_requests))
    
    # Extract throughput (requests per second) from "finished in X.XXs, YYYY.YY req/s, Z.ZZMB/s" line
    throughput=$(grep "finished in.*req/s" "$h2load_output" | sed -n 's/.*finished in [0-9.]*s, \([0-9.]*\) req\/s.*/\1/p' || echo "0")
    
    # Extract average latency (mean value from time for request line)
    avg_latency=$(grep "time for request:" "$h2load_output" | awk '{print $6}' || echo "0ms")
    # Convert to ms if it's in different units
    if [[ "$avg_latency" == *"us"* ]]; then
        avg_latency=$(echo "$avg_latency" | sed 's/us$//' | awk '{printf "%.2f", $1/1000}')
    elif [[ "$avg_latency" == *"ms"* ]]; then
        avg_latency=$(echo "$avg_latency" | sed 's/ms$//')
    elif [[ "$avg_latency" == *"s"* ]]; then
        avg_latency=$(echo "$avg_latency" | sed 's/s$//' | awk '{printf "%.2f", $1*1000}')
    fi
    
    # Calculate error rate
    if [ "$total_requests" -gt 0 ]; then
        error_rate=$(awk "BEGIN {printf \"%.2f\", ($failed_requests/$total_requests)*100}")
    else
        error_rate="0.00"
    fi
    
    # Ensure variables have default values
    total_requests=${total_requests:-0}
    throughput=${throughput:-0}
    avg_latency=${avg_latency:-0}
    
    # Generate simplified CSV entry
    echo "${SERVICE},${total_requests},${DURATION},${throughput},${avg_latency},${error_rate}" >> "$csv_output"
    
    echo "Generated simplified CSV report with $total_requests total requests"
    echo "Successful requests: $successful_requests"
    echo "Failed requests: $failed_requests"
    echo "Throughput: ${throughput} req/s"
    echo "Average latency: ${avg_latency} ms"
    echo "Error rate: ${error_rate}%"
else
    echo "Warning: h2load output file not found"
fi

echo "Quick test completed!"
echo "Results saved to: ${RESULTS_DIR}/"
echo "Service log: ${RESULTS_DIR}/${SERVICE}.log"
echo "Backend log: ${RESULTS_DIR}/netty_backend.log"