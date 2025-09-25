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
# Extended matrix for HTTP/1.1 and HTTP/2 combinations
SERVICE_NAMES=("h1-h1" "h1c-h1" "h1-h1c" "h1c-h1c" "h2-h2" "h2c-h2" "h2-h2c" "h2c-h2c" "h1-h2" "h1c-h2" "h1-h2c" "h1c-h2c" "h2-h1" "h2c-h1" "h2-h1c" "h2c-h1c")
SERVICE_PORTS=(9091 9092 9093 9094 9095 9096 9097 9098 9099 9100 9101 9102 9103 9104 9105 9106)
SERVICE_PROTOCOLS=("https" "http" "https" "http" "https" "http" "https" "http" "https" "http" "https" "http" "https" "http" "https" "http")
SERVICE_CLIENT_SSL=(true true false false true true false false true true false false true true false false)
SERVICE_SERVER_SSL=(true false true false true false true false true false true false true false true false)
SERVICE_CLIENT_HTTP2=(false false false false true true true true false false false false true true true true)
SERVICE_SERVER_HTTP2=(false false false false true true true true false false false false false false false false)
SERVICE_BACKEND_SSL=(true true false false true true false false true true false false true true false false)
SERVICE_BACKEND_HTTP2=(false false false false true true true true true true true true false false false false)
SERVICE_BACKEND_PORTS=(8689 8700 8688 8701 8691 8702 8690 8703 8693 8704 8692 8705 8706 8707 8708 8709)

# Payload options
PAYLOADS=("1KB" "10KB" "100KB" "1MB" "50B")

# Function to display help
show_help() {
    cat << EOF
Ballerina HTTP Load Testing - Quick Test Script

USAGE:
    ./quick_test.sh [OPTIONS] <service> <file_size> <users> <duration>

ARGUMENTS:
    <service>       Service configuration name (see SERVICE CONFIGURATIONS below)
    <file_size>     Payload size (e.g., 1KB, 5KB, 10KB, 100KB, 500KB, 1MB)
    <users>         Number of concurrent users/connections
    <duration>      Test duration in seconds

OPTIONS:
    -h, --help      Show this help message and exit

EXAMPLES:
    # Basic HTTP/1.1 test
    ./quick_test.sh h1c-h1c 1KB 10 30

    # HTTP/2 with SSL test
    ./quick_test.sh h2-h2 10KB 50 60

    # Mixed protocol scenario
    ./quick_test.sh h1-h2c 5KB 25 45

SERVICE CONFIGURATIONS:
    The framework supports 16 service configurations combining HTTP/1.1, HTTP/2, SSL, and clear text:

    Pure HTTP/1.1 (Original):
    ┌─────────┬─────────────────┬─────────────────┬─────────────────┬──────┐
    │ Service │ Client Protocol │ Server Protocol │ Backend Protocol│ Port │
    ├─────────┼─────────────────┼─────────────────┼─────────────────┼──────┤
    │ h1-h1   │ HTTP/1.1+SSL    │ HTTP/1.1+SSL    │ HTTP/1.1+SSL    │ 9091 │
    │ h1c-h1  │ HTTP/1.1+SSL    │ HTTP/1.1        │ HTTP/1.1+SSL    │ 9092 │
    │ h1-h1c  │ HTTP/1.1+SSL    │ HTTP/1.1+SSL    │ HTTP/1.1        │ 9093 │
    │ h1c-h1c │ HTTP/1.1        │ HTTP/1.1        │ HTTP/1.1        │ 9094 │
    └─────────┴─────────────────┴─────────────────┴─────────────────┴──────┘

    Pure HTTP/2 (New):
    ┌─────────┬─────────────────┬─────────────────┬─────────────────┬──────┐
    │ Service │ Client Protocol │ Server Protocol │ Backend Protocol│ Port │
    ├─────────┼─────────────────┼─────────────────┼─────────────────┼──────┤
    │ h2-h2   │ HTTP/2+SSL      │ HTTP/2+SSL      │ HTTP/2+SSL      │ 9095 │
    │ h2c-h2  │ HTTP/2+SSL      │ HTTP/2          │ HTTP/2+SSL      │ 9096 │
    │ h2-h2c  │ HTTP/2+SSL      │ HTTP/2+SSL      │ HTTP/2          │ 9097 │
    │ h2c-h2c │ HTTP/2          │ HTTP/2          │ HTTP/2          │ 9098 │
    └─────────┴─────────────────┴─────────────────┴─────────────────┴──────┘

    Mixed HTTP/1.1 Client → HTTP/2 Backend (New):
    ┌─────────┬─────────────────┬─────────────────┬─────────────────┬──────┐
    │ Service │ Client Protocol │ Server Protocol │ Backend Protocol│ Port │
    ├─────────┼─────────────────┼─────────────────┼─────────────────┼──────┤
    │ h1-h2   │ HTTP/1.1+SSL    │ HTTP/1.1+SSL    │ HTTP/2+SSL      │ 9099 │
    │ h1c-h2  │ HTTP/1.1+SSL    │ HTTP/1.1        │ HTTP/2+SSL      │ 9100 │
    │ h1-h2c  │ HTTP/1.1+SSL    │ HTTP/1.1+SSL    │ HTTP/2          │ 9101 │
    │ h1c-h2c │ HTTP/1.1        │ HTTP/1.1        │ HTTP/2          │ 9102 │
    └─────────┴─────────────────┴─────────────────┴─────────────────┴──────┘

    Mixed HTTP/2 Client → HTTP/1.1 Backend (New):
    ┌─────────┬─────────────────┬─────────────────┬─────────────────┬──────┐
    │ Service │ Client Protocol │ Server Protocol │ Backend Protocol│ Port │
    ├─────────┼─────────────────┼─────────────────┼─────────────────┼──────┤
    │ h2-h1   │ HTTP/2+SSL      │ HTTP/2+SSL      │ HTTP/1.1+SSL    │ 9103 │
    │ h2c-h1  │ HTTP/2+SSL      │ HTTP/2          │ HTTP/1.1+SSL    │ 9104 │
    │ h2-h1c  │ HTTP/2+SSL      │ HTTP/2+SSL      │ HTTP/1.1        │ 9105 │
    │ h2c-h1c │ HTTP/2          │ HTTP/2          │ HTTP/1.1        │ 9106 │
    └─────────┴─────────────────┴─────────────────┴─────────────────┴──────┘

NAMING CONVENTION:
    Service names follow: {client_protocol}-{backend_protocol}
    • h1  = HTTP/1.1 with SSL/TLS (HTTPS)
    • h1c = HTTP/1.1 clear text (HTTP)
    • h2  = HTTP/2 with SSL/TLS (HTTPS)
    • h2c = HTTP/2 clear text (HTTP)

PERFORMANCE TESTING:
    Compare protocols:
    • h1c-h1c vs h2c-h2c  (HTTP/1.1 vs HTTP/2 clear text)
    • h1-h1 vs h2-h2       (HTTP/1.1 vs HTTP/2 with SSL)
    
    Test mixed scenarios:
    • h1-h2 vs h2-h1       (Protocol translation overhead)
    
    Migration testing:
    • h1-h1 → h1-h2 → h2-h2 (Gradual HTTP/2 adoption)

OUTPUT:
    Results are saved to quick_results/ directory:
    • Service logs: quick_results/{service}.log
    • h2load output: quick_results/h2load_raw_{service}_{size}_{users}users.txt
    • CSV report: quick_results/quick_test_{service}_{size}_{users}users.csv

PREREQUISITES:
    • Ballerina (built JAR in ballerina-passthrough/target/bin/)
    • Netty backend (built JAR in netty-backend/target/)
    • h2load (HTTP/2 benchmarking tool)

SEE ALSO:
    • ./run_load_tests.sh    - Run comprehensive load tests
    • ./http2_demo.sh        - Interactive HTTP/2 demonstration
    • ./validate_setup.sh    - Validate environment setup
    • HTTP2_EXTENSION.md     - Detailed HTTP/2 documentation

EOF
}

# Check for help flags
if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
    show_help
    exit 0
fi

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

get_service_client_http2() {
    local service=$1
    for i in "${!SERVICE_NAMES[@]}"; do
        if [ "${SERVICE_NAMES[$i]}" = "$service" ]; then
            echo "${SERVICE_CLIENT_HTTP2[$i]}"
            return
        fi
    done
}

get_service_server_http2() {
    local service=$1
    for i in "${!SERVICE_NAMES[@]}"; do
        if [ "${SERVICE_NAMES[$i]}" = "$service" ]; then
            echo "${SERVICE_SERVER_HTTP2[$i]}"
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

get_service_backend_http2() {
    local service=$1
    for i in "${!SERVICE_NAMES[@]}"; do
        if [ "${SERVICE_NAMES[$i]}" = "$service" ]; then
            echo "${SERVICE_BACKEND_HTTP2[$i]}"
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
CLIENT_HTTP2=$(get_service_client_http2 "$SERVICE")
SERVER_HTTP2=$(get_service_server_http2 "$SERVICE")
BACKEND_SSL=$(get_service_backend_ssl "$SERVICE")
BACKEND_HTTP2=$(get_service_backend_http2 "$SERVICE")
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
echo "Service: Client HTTP$([ "$CLIENT_HTTP2" = "true" ] && echo "2" || echo "1.1")/SSL=$CLIENT_SSL -> Server HTTP$([ "$SERVER_HTTP2" = "true" ] && echo "2" || echo "1.1")/SSL=$SERVER_SSL"
echo "Backend: HTTP$([ "$BACKEND_HTTP2" = "true" ] && echo "2" || echo "1.1")/SSL=$BACKEND_SSL on port $BACKEND_PORT"

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
    nohup java -jar "$NETTY_JAR" --port $BACKEND_PORT --ssl true --http2 $BACKEND_HTTP2 --key-store-file "${PROJECT_ROOT}/resources/ballerinaKeystore.p12" --key-store-password ballerina > "$RESULTS_DIR/netty_backend.log" 2>&1 &
else
    nohup java -jar "$NETTY_JAR" --port $BACKEND_PORT --ssl false --http2 $BACKEND_HTTP2 > "$RESULTS_DIR/netty_backend.log" 2>&1 &
fi
BACKEND_PID=$!
echo "Backend started with PID: $BACKEND_PID"

# Wait for backend to start
sleep 20

# Check if backend is running
if ! lsof -Pi :$BACKEND_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "Error: Backend failed to start on port $BACKEND_PORT"
    exit 1
fi

# Start Ballerina service
echo "Starting Ballerina service..."
echo "Configuration: clientSsl=$CLIENT_SSL, serverSsl=$SERVER_SSL, clientHttp2=$CLIENT_HTTP2, serverHttp2=$SERVER_HTTP2, port=$PORT"
cd "$BALLERINA_PROJECT_DIR"
echo "Current directory: $(pwd)"
echo "JAR file: $BALLERINA_JAR"
echo "JAR exists: $(test -f "$BALLERINA_JAR" && echo "yes" || echo "no")"

nohup java -jar "$BALLERINA_JAR" \
    -CclientSsl=$CLIENT_SSL \
    -CserverSsl=$SERVER_SSL \
    -CclientHttp2=$CLIENT_HTTP2 \
    -CserverHttp2=$SERVER_HTTP2 \
    -CserverPort=$PORT \
    -CbackendPort=$BACKEND_PORT \
    > "$RESULTS_DIR/${SERVICE}.log" 2>&1 &
SERVICE_PID=$!
echo "Service started with PID: $SERVICE_PID"

# Wait for service to start
sleep 20

# Check if service is running
if ! lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "Error: Service failed to start on port $PORT"
    echo "Attempting to show service log:"
    cat "$RESULTS_DIR/${SERVICE}.log" 2>/dev/null || echo "No service log available"
    echo "Checking if process is still running:"
    ps -p $SERVICE_PID >/dev/null 2>&1 && echo "Service process is still running" || echo "Service process has exited"
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
        "50B") head -c 50 /dev/urandom > "$DATA_FILE" 2>/dev/null ;;
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

# Determine if we should force HTTP/1.1 or use HTTP/2
# h2load uses HTTP/2 by default for HTTPS connections, HTTP/1.1 for HTTP connections
# We need to force HTTP/1.1 when testing h1/h1c scenarios
if [[ "$SERVICE" =~ ^h1 ]]; then
    # Force HTTP/1.1 for services that start with h1
    H2LOAD_HTTP_VERSION="--h1"
    echo "Forcing HTTP/1.1 client protocol"
else
    # Use default (HTTP/2 for HTTPS, HTTP/1.1 for HTTP)
    H2LOAD_HTTP_VERSION=""
    if [ "$PROTOCOL" = "https" ]; then
        echo "Using HTTP/2 client protocol (default for HTTPS)"
    else
        echo "Using HTTP/1.1 client protocol (default for HTTP)"
    fi
fi

# Run h2load with the data file as POST body (show output in terminal and save to file)
if [ "$PROTOCOL" = "https" ]; then
    # For HTTPS
    h2load -c "$USERS" -t 1 -D "$DURATION" -d "$DATA_FILE" \
        $H2LOAD_HTTP_VERSION "$TEST_URL" 2>&1 | tee "$h2load_output"
else
    # For HTTP
    h2load -c "$USERS" -t 1 -D "$DURATION" -d "$DATA_FILE" \
        $H2LOAD_HTTP_VERSION "$TEST_URL" 2>&1 | tee "$h2load_output"
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