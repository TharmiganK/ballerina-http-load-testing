#!/bin/bash

# Ballerina Passthrough Load Testing Script
# This script builds the unified Ballerina project, starts services, and performs load tests

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="${PROJECT_ROOT}/results"
REPORTS_DIR="${PROJECT_ROOT}/reports"
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

# Default test parameters
DEFAULT_FILE_SIZES=("50B" "1KB" "10KB" "100KB" "500KB" "1MB")
DEFAULT_CONCURRENT_USERS=(50 100 500)
DEFAULT_SERVICE_NAMES=("h1-h1" "h1c-h1" "h1-h1c" "h1c-h1c" "h2-h2" "h2c-h2" "h2-h2c" "h2c-h2c" "h1-h2" "h1c-h2" "h1-h2c" "h1c-h2c" "h2-h1" "h2c-h1" "h2-h1c" "h2c-h1c")

# Current test parameters (will be set by parse_arguments or defaults)
FILE_SIZES=()
CONCURRENT_USERS=()
SELECTED_SERVICE_NAMES=()
TEST_DURATION=300  # 5 minutes per test
RAMP_UP_TIME=30    # 30 seconds ramp up

# Restart timing configuration
BACKEND_RESTART_WAIT=20    # seconds to wait after restarting backends
SERVICE_RESTART_WAIT=20   # seconds to wait after restarting service
PRE_TEST_WAIT=30           # seconds to wait before starting test

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Function to parse command line arguments for test customization
parse_arguments() {
    # Set defaults
    FILE_SIZES=("${DEFAULT_FILE_SIZES[@]}")
    CONCURRENT_USERS=("${DEFAULT_CONCURRENT_USERS[@]}")
    SELECTED_SERVICE_NAMES=("${DEFAULT_SERVICE_NAMES[@]}")
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --file-sizes|--files|-f)
                if [ -z "$2" ]; then
                    error "File sizes argument requires values"
                    exit 1
                fi
                IFS=',' read -ra FILE_SIZES <<< "$2"
                shift 2
                ;;
            --users|-u)
                if [ -z "$2" ]; then
                    error "Users argument requires values"
                    exit 1
                fi
                IFS=',' read -ra CONCURRENT_USERS <<< "$2"
                shift 2
                ;;
            --services|-s)
                if [ -z "$2" ]; then
                    error "Services argument requires values"
                    exit 1
                fi
                IFS=',' read -ra SELECTED_SERVICE_NAMES <<< "$2"
                # Validate service names
                for service in "${SELECTED_SERVICE_NAMES[@]}"; do
                    if [[ ! " ${SERVICE_NAMES[*]} " =~ " ${service} " ]]; then
                        error "Invalid service name: $service"
                        error "Valid services: ${SERVICE_NAMES[*]}"
                        exit 1
                    fi
                done
                shift 2
                ;;
            --duration|-d)
                if [ -z "$2" ] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    error "Duration must be a positive number (seconds)"
                    exit 1
                fi
                TEST_DURATION="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Validate file sizes
    for size in "${FILE_SIZES[@]}"; do
        if [[ ! "$size" =~ ^[0-9]+(B|KB|MB)$ ]]; then
            error "Invalid file size format: $size (use format like 1KB, 10KB, 1MB)"
            exit 1
        fi
    done
    
    # Validate concurrent users
    for users in "${CONCURRENT_USERS[@]}"; do
        if ! [[ "$users" =~ ^[0-9]+$ ]] || [ "$users" -le 0 ]; then
            error "Invalid number of users: $users (must be positive integer)"
            exit 1
        fi
    done
    
    info "Test configuration:"
    info "  File sizes: ${FILE_SIZES[*]}"
    info "  Concurrent users: ${CONCURRENT_USERS[*]}"
    info "  Services: ${SELECTED_SERVICE_NAMES[*]}"
    info "  Test duration: ${TEST_DURATION} seconds"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Ballerina is installed
    if ! command -v bal &> /dev/null; then
        error "Ballerina is not installed. Please install Ballerina first."
        exit 1
    fi
    
    # Check if Maven is installed
    if ! command -v mvn &> /dev/null; then
        error "Maven is not installed. Please install Maven first."
        echo "You can install Maven using: brew install maven"
        exit 1
    fi
    
    # Check if h2load is installed
    if ! command -v h2load &> /dev/null; then
        error "h2load is not installed. Please install h2load first."
        echo "You can install h2load using: brew install nghttp2 (macOS) or sudo apt-get install nghttp2-client (Ubuntu/Debian)"
        exit 1
    fi
    
    # Check if Java is installed
    if ! command -v java &> /dev/null; then
        error "Java is not installed. Please install Java first."
        exit 1
    fi
    
    log "All prerequisites are met."
}

# Function to ensure sample files exist
ensure_sample_files() {
    log "Checking sample files..."
    
    local sample_files=("1KB.txt" "5KB.txt" "10KB.txt" "100KB.txt" "500KB.txt" "1MB.txt")
    local missing_files=()
    
    for file in "${sample_files[@]}"; do
        if [ ! -f "${PROJECT_ROOT}/samples/${file}" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        warn "Missing sample files: ${missing_files[*]}"
        
        if [ -f "${SCRIPT_DIR}/generate_samples.sh" ]; then
            log "Generating missing sample files..."
            cd "${SCRIPT_DIR}"
            ./generate_samples.sh
            log "Sample files generated successfully"
        else
            error "Sample generator script not found. Cannot create missing sample files."
            exit 1
        fi
    else
        log "All sample files exist"
    fi
}

# Function to build Ballerina project
build_ballerina_project() {
    log "Building Ballerina project..."
    
    cd "${BALLERINA_PROJECT_DIR}"
    
    # Clean previous build artifacts
    log "Cleaning previous build artifacts..."
    bal clean
    
    # Remove Dependencies.toml if it exists
    if [ -f "Dependencies.toml" ]; then
        log "Removing existing Dependencies.toml"
        rm -f Dependencies.toml
    fi
    
    if ! bal build; then
        error "Failed to build Ballerina project"
        exit 1
    fi
    
    if [ ! -f "$BALLERINA_JAR" ]; then
        error "Ballerina JAR not found after build: $BALLERINA_JAR"
        exit 1
    fi
    
    log "Ballerina project built successfully"
    cd "${PROJECT_ROOT}"
}

# Function to build netty backend project
build_netty_backend() {
    log "Building Netty backend project..."
    
    cd "${NETTY_BACKEND_DIR}"
    
    # Clean previous build artifacts
    log "Cleaning previous build artifacts..."
    mvn clean
    
    # Build the project
    if ! mvn package -DskipTests; then
        error "Failed to build Netty backend project"
        exit 1
    fi
    
    # Wait a moment for file system to sync
    sleep 1
    
    if [ ! -f "$NETTY_JAR" ]; then
        error "Netty JAR not found after build: $NETTY_JAR"
        error "Available files in target directory:"
        ls -la "${NETTY_BACKEND_DIR}/target/" || true
        exit 1
    fi
    
    log "Netty backend project built successfully"
    cd "${PROJECT_ROOT}"
}

# Function to start netty backend
start_backend() {
    local use_ssl=$1
    local backend_port=$2
    local use_http2=$3
    
    local backend_type=$([ "$use_ssl" = "true" ] && echo "HTTPS" || echo "HTTP")
    local http_version=$([ "$use_http2" = "true" ] && echo "HTTP/2" || echo "HTTP/1.1")
    log "Starting netty backend ($backend_type, $http_version) on port $backend_port..."
    
    # Stop existing backend if running
    stop_backend
    
    # Build command with SSL and HTTP/2 options
    local cmd="java -jar $NETTY_JAR --ssl $use_ssl --http2 $use_http2 --port $backend_port"
    if [ "$use_ssl" = "true" ]; then
        cmd="$cmd --key-store-file ${PROJECT_ROOT}/resources/ballerinaKeystore.p12 --key-store-password ballerina"
    fi
    
    # Start backend in background
    cd "${NETTY_BACKEND_DIR}"
    
    nohup $cmd > "${RESULTS_DIR}/netty_backend.log" 2>&1 &
    local backend_pid=$!
    echo $backend_pid > "${RESULTS_DIR}/netty_backend.pid"
    
    info "Backend started with PID: $backend_pid, waiting for port $backend_port to be ready..."
    
    # Wait for backend to start
    local timeout=15
    local count=0
    while [ $count -lt $timeout ]; do
        if lsof -Pi :$backend_port -sTCP:LISTEN -t >/dev/null 2>&1; then
            log "Netty backend ($backend_type, $http_version) started successfully on port $backend_port (PID: $backend_pid)"
            sleep $BACKEND_RESTART_WAIT
            return 0
        fi
        
        # Check if process is still running
        if ! kill -0 "$backend_pid" 2>/dev/null; then
            error "Netty backend process died unexpectedly"
            if [ "$use_ssl" = "true" ] && grep -q "UnsatisfiedLinkError.*netty_tcnative" "${RESULTS_DIR}/netty_backend.log" 2>/dev/null; then
                error "SSL backend failed due to missing native libraries (common on ARM64 systems)"
                error "This is a known issue with Netty SSL on Apple Silicon Macs"
                error "Consider using HTTP backend instead or install native SSL libraries"
            fi
            return 1
        fi
        
        sleep 1
        ((count++))
    done
    
    error "Failed to start netty backend on port $backend_port within $timeout seconds"
    if [ "$use_ssl" = "true" ]; then
        warn "If this is an HTTPS backend, check logs for SSL-related errors"
    fi
    return 1
}

# Function to stop netty backend
stop_backend() {
    local pid_file="${RESULTS_DIR}/netty_backend.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            info "Stopping netty backend (PID: $pid)..."
            kill "$pid"
            sleep 2
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                warn "Force killing netty backend..."
                kill -9 "$pid"
            fi
        fi
        rm -f "$pid_file"
    fi
    
    # Also kill any remaining netty processes
    pkill -f "netty-http-echo-service.jar" 2>/dev/null || true
}

# Function to start Ballerina service
start_service() {
    local service=$1
    local port=$(get_service_port "$service")
    local client_ssl=$(get_service_client_ssl "$service")
    local server_ssl=$(get_service_server_ssl "$service")
    local client_http2=$(get_service_client_http2 "$service")
    local server_http2=$(get_service_server_http2 "$service")
    local backend_port=$(get_service_backend_port "$service")
    
    info "Starting Ballerina service: $service (port: $port, clientSsl: $client_ssl, serverSsl: $server_ssl, clientHttp2: $client_http2, serverHttp2: $server_http2, backendPort: $backend_port)"
    
    # Stop existing service if running
    stop_service
    
    # Check if port is available
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        warn "Port $port is already in use. Attempting to kill existing process..."
        kill $(lsof -t -i:$port) 2>/dev/null || true
        sleep 2
    fi
    
    # Start the service in background
    cd "${BALLERINA_PROJECT_DIR}"
    nohup java -jar "$BALLERINA_JAR" \
        -CclientSsl=$client_ssl \
        -CserverSsl=$server_ssl \
        -CclientHttp2=$client_http2 \
        -CserverHttp2=$server_http2 \
        -CserverPort=$port \
        -CbackendPort=$backend_port \
        > "${RESULTS_DIR}/${service}.log" 2>&1 &
    local service_pid=$!
    echo $service_pid > "${RESULTS_DIR}/ballerina_service.pid"
    
    # Wait for service to start
    local timeout=20
    local count=0
    while [ $count -lt $timeout ]; do
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            log "Ballerina service $service started successfully on port $port (PID: $service_pid)"
            sleep $SERVICE_RESTART_WAIT
            return 0
        fi
        sleep 1
        ((count++))
    done
    
    error "Failed to start Ballerina service $service on port $port within $timeout seconds"
    return 1
}

# Function to stop Ballerina service
stop_service() {
    local pid_file="${RESULTS_DIR}/ballerina_service.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            info "Stopping Ballerina service (PID: $pid)..."
            kill "$pid"
            sleep 2
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                warn "Force killing Ballerina service..."
                kill -9 "$pid"
            fi
        fi
        rm -f "$pid_file"
    fi
    
    # Also kill any remaining Ballerina processes
    pkill -f "ballerina_passthrough.jar" 2>/dev/null || true
}

# Function to run load test
run_load_test() {
    local service=$1
    local file_size=$2
    local users=$3
    local port=$(get_service_port "$service")
    local protocol=$(get_service_protocol "$service")
    
    local test_name="${service}_${file_size}_${users}users"
    local result_file="${RESULTS_DIR}/${test_name}.csv"
    
    info "Running load test: $test_name"
    info "Service: $service, File Size: $file_size, Users: $users, Protocol: $protocol, Port: $port"
    
    # Wait before starting test
    sleep $PRE_TEST_WAIT
    
    # Remove existing result file
    rm -f "$result_file"
    
    # Prepare data file based on payload size
    data_file="${RESULTS_DIR}/test_payload_${file_size}.txt"
    if [ -f "${PROJECT_ROOT}/samples/${file_size}.txt" ]; then
        cp "${PROJECT_ROOT}/samples/${file_size}.txt" "$data_file"
    else
        warn "Sample file not found, creating placeholder data"
        case "$file_size" in
            "1KB") dd if=/dev/zero bs=1024 count=1 | tr '\0' 'A' > "$data_file" 2>/dev/null ;;
            "5KB") dd if=/dev/zero bs=1024 count=5 | tr '\0' 'A' > "$data_file" 2>/dev/null ;;
            "10KB") dd if=/dev/zero bs=1024 count=10 | tr '\0' 'A' > "$data_file" 2>/dev/null ;;
            "100KB") dd if=/dev/zero bs=1024 count=100 | tr '\0' 'A' > "$data_file" 2>/dev/null ;;
            "500KB") dd if=/dev/zero bs=1024 count=500 | tr '\0' 'A' > "$data_file" 2>/dev/null ;;
            "1MB") dd if=/dev/zero bs=1024 count=1024 | tr '\0' 'A' > "$data_file" 2>/dev/null ;;
            "50B") dd if=/dev/zero bs=1 count=50 | tr '\0' 'A' > "$data_file" 2>/dev/null ;;
            *) echo "A" > "$data_file" ;;
        esac
    fi
    
    # Build h2load URL
    test_url="${protocol}://localhost:${port}/passthrough"
    
    # Run h2load test
    h2load_output="${RESULTS_DIR}/${test_name}_h2load.txt"
    
    echo "Running h2load test for $service $file_size with $users users..."
    
    # Determine if we should force HTTP/1.1 or use HTTP/2
    # h2load uses HTTP/2 by default for HTTPS connections, HTTP/1.1 for HTTP connections
    # We need to force HTTP/1.1 when testing h1/h1c scenarios
    if [[ "$service" =~ ^h1 ]]; then
        # Force HTTP/1.1 for services that start with h1
        H2LOAD_HTTP_VERSION="--h1"
        echo "Forcing HTTP/1.1 client protocol"
    else
        # Use default (HTTP/2 for HTTPS, HTTP/1.1 for HTTP)
        H2LOAD_HTTP_VERSION=""
        if [ "$protocol" = "https" ]; then
            echo "Using HTTP/2 client protocol (default for HTTPS)"
        else
            echo "Using HTTP/1.1 client protocol (default for HTTP)"
        fi
    fi
    
    if [ "$protocol" = "https" ]; then
        # For HTTPS
        h2load -c "$users" -t 1 -D "$TEST_DURATION" -d "$data_file" \
            $H2LOAD_HTTP_VERSION "$test_url" 2>&1 | tee "$h2load_output"
    else
        # For HTTP
        h2load -c "$users" -t 1 -D "$TEST_DURATION" -d "$data_file" \
            $H2LOAD_HTTP_VERSION "$test_url" 2>&1 | tee "$h2load_output"
    fi
    
    # Convert h2load output to simplified CSV format
    if [ -f "$h2load_output" ]; then
        # Create simplified CSV header
        echo "test_type,total_requests,duration_sec,throughput_rps,avg_latency_ms,error_rate_percent" > "$result_file"
        
        # Extract metrics from h2load output
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
        test_identifier="${service}_${file_size}_${users}users"
        echo "${test_identifier},${total_requests},${TEST_DURATION},${throughput},${avg_latency},${error_rate}" >> "$result_file"
        
        info "Generated CSV with $total_requests total requests ($successful_requests successful, $failed_requests failed)"
        info "Throughput: ${throughput} req/s, Average latency: ${avg_latency} ms, Error rate: ${error_rate}%"
        
        log "Load test completed: $test_name (${total_requests} requests, ${successful_requests} successful)"
        return 0
    else
        error "Load test failed: $test_name"
        return 1
    fi
}

# Function to generate HTML reports
generate_reports() {
    log "Generating HTML reports..."
    
    for service in "${SELECTED_SERVICE_NAMES[@]}"; do
        for file_size in "${FILE_SIZES[@]}"; do
            for users in "${CONCURRENT_USERS[@]}"; do
                local test_name="${service}_${file_size}_${users}users"
                local result_file="${RESULTS_DIR}/${test_name}.csv"
                local h2load_file="${RESULTS_DIR}/${test_name}_h2load.txt"
                local report_dir="${REPORTS_DIR}/${test_name}"
                
                if [ -f "$result_file" ] && [ -f "$h2load_file" ]; then
                    info "Generating report for $test_name..."
                    
                    # Remove existing report directory
                    if [ -d "$report_dir" ]; then
                        rm -rf "$report_dir"
                    fi
                    mkdir -p "$report_dir"
                    
                    # Generate simple HTML report from h2load output
                    generate_h2load_html_report "$h2load_file" "$result_file" "$report_dir" "$test_name"
                    
                    if [ $? -eq 0 ]; then
                        log "Report generated: $report_dir/index.html"
                    else
                        warn "Failed to generate report for $test_name"
                    fi
                fi
            done
        done
    done
}

# Function to generate HTML report from h2load output
generate_h2load_html_report() {
    local h2load_file="$1"
    local csv_file="$2"
    local report_dir="$3"
    local test_name="$4"
    
    local html_file="${report_dir}/index.html"
    
    # Extract metrics from h2load output
    local total_requests=$(grep "requests:" "$h2load_file" | awk '{print $2}' || echo "0")
    local successful_requests=$(grep "status codes:" "$h2load_file" | awk '{print $3}' || echo "0")
    local failed_requests=$((total_requests - successful_requests))
    local req_per_sec=$(grep "req/s" "$h2load_file" | awk '{print $2}' || echo "0")
    local avg_time=$(grep "time for request:" "$h2load_file" | awk '{print $4}' | sed 's/us$//' | sed 's/ms$//' || echo "0")
    local min_time=$(grep "time for request:" "$h2load_file" | awk '{print $2}' | sed 's/us$//' | sed 's/ms$//' || echo "0")
    local max_time=$(grep "max:" "$h2load_file" | awk '{print $4}' | sed 's/ms//' || echo "0")
    local success_rate=$(echo "$successful_requests $total_requests" | awk '{if($2>0) printf "%.2f", ($1/$2)*100; else print "0"}')
    
    # Generate HTML report
    cat > "$html_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Load Test Report - $test_name</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f4f4f4; padding: 10px; border-radius: 5px; }
        .metrics { display: flex; flex-wrap: wrap; gap: 20px; margin: 20px 0; }
        .metric { background: #e9e9e9; padding: 15px; border-radius: 5px; min-width: 200px; }
        .metric h3 { margin: 0; color: #333; }
        .metric .value { font-size: 24px; font-weight: bold; color: #007acc; }
        .success { color: #28a745; }
        .error { color: #dc3545; }
        pre { background: #f8f9fa; padding: 15px; border-radius: 5px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Load Test Report</h1>
        <h2>Test: $test_name</h2>
        <p>Generated on: $(date)</p>
    </div>
    
    <div class="metrics">
        <div class="metric">
            <h3>Total Requests</h3>
            <div class="value">$total_requests</div>
        </div>
        <div class="metric">
            <h3>Successful Requests</h3>
            <div class="value success">$successful_requests</div>
        </div>
        <div class="metric">
            <h3>Failed Requests</h3>
            <div class="value error">$failed_requests</div>
        </div>
        <div class="metric">
            <h3>Success Rate</h3>
            <div class="value">$success_rate%</div>
        </div>
        <div class="metric">
            <h3>Requests/sec</h3>
            <div class="value">$req_per_sec</div>
        </div>
        <div class="metric">
            <h3>Avg Response Time</h3>
            <div class="value">${avg_time}ms</div>
        </div>
        <div class="metric">
            <h3>Min Response Time</h3>
            <div class="value">${min_time}ms</div>
        </div>
        <div class="metric">
            <h3>Max Response Time</h3>
            <div class="value">${max_time}ms</div>
        </div>
    </div>
    
    <h3>Raw h2load Output</h3>
    <pre>$(cat "$h2load_file")</pre>
    
    <h3>CSV Data Sample (first 10 rows)</h3>
    <pre>$(head -n 11 "$csv_file")</pre>
</body>
</html>
EOF
    
    return 0
}

# Function to create summary report
create_summary_report() {
    log "Creating summary report..."
    
    local summary_file="${REPORTS_DIR}/load_test_summary.html"
    
    cat > "$summary_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Ballerina Passthrough Load Test Summary</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .service-h1-h1 { background-color: #ffebee; }
        .service-h1c-h1 { background-color: #e8f5e8; }
        .service-h1-h1c { background-color: #e3f2fd; }
        .service-h1c-h1c { background-color: #fff3e0; }
        .header { background-color: #2196F3; color: white; padding: 20px; text-align: center; }
        .metrics { display: flex; flex-wrap: wrap; gap: 20px; margin: 20px 0; }
        .metric-card { background: #f5f5f5; padding: 15px; border-radius: 8px; flex: 1; min-width: 200px; }
        .report-link { color: #2196F3; text-decoration: none; }
        .report-link:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Ballerina Passthrough Service Load Test Results</h1>
        <p>Generated on: $(date)</p>
    </div>
    
    <div class="metrics">
        <div class="metric-card">
            <h3>Service Types Tested</h3>
            <ul>
                <li><strong>h1-h1:</strong> HTTPS → HTTPS</li>
                <li><strong>h1c-h1:</strong> HTTP → HTTPS</li>
                <li><strong>h1-h1c:</strong> HTTPS → HTTP</li>
                <li><strong>h1c-h1c:</strong> HTTP → HTTP</li>
            </ul>
        </div>
        <div class="metric-card">
            <h3>Test Parameters</h3>
            <ul>
                <li><strong>File Sizes:</strong> ${FILE_SIZES[*]}</li>
                <li><strong>Concurrent Users:</strong> ${CONCURRENT_USERS[*]}</li>
                <li><strong>Test Duration:</strong> ${TEST_DURATION}s</li>
                <li><strong>Ramp-up Time:</strong> ${RAMP_UP_TIME}s</li>
            </ul>
        </div>
    </div>
    
    <h2>Detailed Test Reports</h2>
    <table>
        <tr>
            <th>Service Type</th>
            <th>File Size</th>
            <th>Concurrent Users</th>
            <th>Detailed Report</th>
        </tr>
EOF

    # Add table rows for each test
    for service in "${SELECTED_SERVICE_NAMES[@]}"; do
        for file_size in "${FILE_SIZES[@]}"; do
            for users in "${CONCURRENT_USERS[@]}"; do
                local test_name="${service}_${file_size}_${users}users"
                local report_dir="${REPORTS_DIR}/${test_name}"
                
                if [ -d "$report_dir" ]; then
                    echo "        <tr class=\"service-$service\">" >> "$summary_file"
                    echo "            <td>$service</td>" >> "$summary_file"
                    echo "            <td>$file_size</td>" >> "$summary_file"
                    echo "            <td>$users</td>" >> "$summary_file"
                    echo "            <td><a href=\"${test_name}/index.html\" class=\"report-link\">View Report</a></td>" >> "$summary_file"
                    echo "        </tr>" >> "$summary_file"
                fi
            done
        done
    done
    
    cat >> "$summary_file" << 'EOF'
    </table>
    
    <h2>Notes</h2>
    <ul>
        <li>All tests were performed against a local netty echo backend service</li>
        <li>SSL/TLS configurations use self-signed certificates from the resources directory</li>
        <li>Response time assertions validate 200 HTTP status codes</li>
        <li>Each test runs for 5 minutes with a 30-second ramp-up period</li>
        <li>Services and backends are restarted between each test scenario for clean state</li>
    </ul>
</body>
</html>
EOF
    
    log "Summary report created: $summary_file"
}

# Function to cleanup
cleanup() {
    log "Cleaning up..."
    
    # Stop Ballerina service and backend
    stop_service
    stop_backend
    
    log "Cleanup completed"
}

# Main execution function
main() {
    log "Starting Ballerina Passthrough Load Testing..."
    
    # Create directories
    mkdir -p "$RESULTS_DIR" "$REPORTS_DIR"
    
    # Setup cleanup trap
    trap cleanup EXIT
    
    # Run all steps
    check_prerequisites
    ensure_sample_files
    build_netty_backend
    build_ballerina_project
    
    # Test each service with all combinations - restart between each scenario
    for service in "${SELECTED_SERVICE_NAMES[@]}"; do
        log "Testing service: $service"
        
        local backend_ssl=$(get_service_backend_ssl "$service")
        local backend_http2=$(get_service_backend_http2 "$service")
        local backend_port=$(get_service_backend_port "$service")
        
        # Run tests for all file sizes and user counts
        for file_size in "${FILE_SIZES[@]}"; do
            for users in "${CONCURRENT_USERS[@]}"; do
                log "=== Test Scenario: $service, $file_size, $users users ==="
                
                # Restart backend for clean state
                if ! start_backend "$backend_ssl" "$backend_port" "$backend_http2"; then
                    error "Failed to start backend for $service, skipping remaining tests"
                    break 3
                fi
                
                # Restart service for clean state  
                if ! start_service "$service"; then
                    error "Failed to start service $service, skipping remaining tests"
                    break 3
                fi
                
                # Run the load test
                if ! run_load_test "$service" "$file_size" "$users"; then
                    warn "Load test failed for $service/$file_size/${users}users, continuing with next test"
                fi
                
                # Stop services after test
                stop_service
                stop_backend
            done
        done
    done
    
    # Generate reports
    generate_reports
    create_summary_report
    
    log "Load testing completed successfully!"
    log "Results available in: $RESULTS_DIR"
    log "HTML reports available in: $REPORTS_DIR"
    log "Summary report: $REPORTS_DIR/load_test_summary.html"
}

# Function to display help
show_help() {
    cat << EOF
Ballerina HTTP Load Testing - Main Load Testing Script

USAGE:
    ./run_load_tests.sh [COMMAND] [OPTIONS]
    ./run_load_tests.sh test [OPTIONS]

COMMANDS:
    build           Build both Netty backend and Ballerina projects
    build-backend   Build only the Netty backend Maven project  
    build-ballerina Build only the Ballerina project
    start-backend   Build and start all netty backends for manual testing
    test            Run complete load testing suite (default)
    reports         Generate HTML reports from existing results
    cleanup         Stop all services and clean up processes
    clean           Clean test results and reports
    help, -h, --help Show this help message

OPTIONS (for 'test' command):
    -f, --file-sizes, --files SIZES    Comma-separated file sizes (e.g., "1KB,10KB,100KB")
    -u, --users USERS                   Comma-separated user counts (e.g., "50,100,500")
    -s, --services SERVICES             Comma-separated service names (e.g., "h1-h1,h2-h2")
    -d, --duration SECONDS              Test duration in seconds (default: 300)
    -h, --help                          Show this help message

DESCRIPTION:
    This script orchestrates comprehensive HTTP load testing across 16 service 
    configurations combining HTTP/1.1, HTTP/2, SSL, and clear text protocols.
    
    The test matrix includes:
    • 4 Pure HTTP/1.1 configurations (h1-h1, h1c-h1, h1-h1c, h1c-h1c)
    • 4 Pure HTTP/2 configurations (h2-h2, h2c-h2, h2-h2c, h2c-h2c)
    • 4 Mixed HTTP/1.1→HTTP/2 configurations (h1-h2, h1c-h2, h1-h2c, h1c-h2c)
    • 4 Mixed HTTP/2→HTTP/1.1 configurations (h2-h1, h2c-h1, h2-h1c, h2c-h1c)

DEFAULT PARAMETERS:
    File sizes:       50B, 1KB, 10KB, 100KB, 500KB, 1MB
    Concurrent users: 50, 100, 500
    Services:         All 16 service configurations
    Test duration:    300 seconds (5 minutes) per test
    
AVAILABLE SERVICES:
    ${SERVICE_NAMES[*]}

AVAILABLE FILE SIZES:
    Any valid format like: 50B, 1KB, 5KB, 10KB, 100KB, 500KB, 1MB
    
OUTPUT:
    Results:        results/ directory with CSV files and detailed logs
    Reports:        reports/ directory with HTML reports and summaries
    
EXAMPLES:
    # Run complete test suite with defaults
    ./run_load_tests.sh
    ./run_load_tests.sh test
    
    # Test specific file sizes
    ./run_load_tests.sh test --file-sizes "1KB,10KB"
    
    # Test with specific user counts
    ./run_load_tests.sh test --users "50,100"
    
    # Test specific services only
    ./run_load_tests.sh test --services "h1-h1,h2-h2"
    
    # Test with custom duration (60 seconds)
    ./run_load_tests.sh test --duration 60
    
    # Combination of options
    ./run_load_tests.sh test -f "1KB,100KB" -u "50,200" -s "h1-h1,h2-h2" -d 120
    
    # Build projects only
    ./run_load_tests.sh build
    
    # Start backends for manual testing
    ./run_load_tests.sh start-backend
    
    # Generate reports from existing results
    ./run_load_tests.sh reports

PREREQUISITES:
    • Ballerina Swan Lake Update 8 or later
    • Maven 3.6.x or later
    • h2load (nghttp2 package)
    • Java 11 or later

SEE ALSO:
    • ./quick_test.sh        - Test individual service configurations
    • ./http2_demo.sh        - Interactive HTTP/2 demonstration  
    • ./validate_setup.sh    - Validate environment setup
    • HTTP2_EXTENSION.md     - Detailed HTTP/2 documentation

EOF
}

# Command line interface
case "${1:-test}" in
    "help"|"-h"|"--help")
        show_help
        exit 0
        ;;
    "build")
        check_prerequisites
        build_netty_backend
        build_ballerina_project
        ;;
    "build-backend")
        check_prerequisites
        build_netty_backend
        ;;
    "build-ballerina")
        check_prerequisites
        build_ballerina_project
        ;;
    "start-backend")
        check_prerequisites
        build_netty_backend
        # Start all backends for manual testing
        start_backend "false" "8688" "false"  # HTTP/1.1 backend
        start_backend "true" "8689" "false"   # HTTPS/1.1 backend  
        start_backend "false" "8690" "true"   # HTTP/2 backend
        start_backend "true" "8691" "true"    # HTTPS/2 backend
        ;;
    "test")
        # Parse test-specific arguments
        shift  # Remove 'test' command
        parse_arguments "$@"
        main
        ;;
    "reports")
        generate_reports
        create_summary_report
        ;;
    "cleanup")
        cleanup
        ;;
    "clean")
        if [ -f "${SCRIPT_DIR}/clean_results.sh" ]; then
            "${SCRIPT_DIR}/clean_results.sh" all
        else
            warn "clean_results.sh not found, cleaning manually..."
            rm -rf "${RESULTS_DIR}"/* "${REPORTS_DIR}"/* 2>/dev/null || true
            log "Results and reports cleaned"
        fi
        ;;
    --file-sizes|--files|-f|--users|-u|--services|-s|--duration|-d)
        # If called with test options but no 'test' command, default to test
        parse_arguments "$@"
        main
        ;;
    *)
        if [ $# -eq 0 ]; then
            # No arguments provided - run default test
            FILE_SIZES=("${DEFAULT_FILE_SIZES[@]}")
            CONCURRENT_USERS=("${DEFAULT_CONCURRENT_USERS[@]}")
            SELECTED_SERVICE_NAMES=("${DEFAULT_SERVICE_NAMES[@]}")
            main
        else
            echo "Usage: $0 [COMMAND] [OPTIONS]"
            echo ""
            echo "Commands:"
            echo "  build           - Build both Netty backend and Ballerina projects"
            echo "  build-backend   - Build only the Netty backend Maven project"
            echo "  build-ballerina - Build only the Ballerina project"
            echo "  start-backend   - Build and start netty backends for manual testing"
            echo "  test [OPTIONS]  - Run load testing suite with optional parameters"
            echo "  reports         - Generate HTML reports from existing results"
            echo "  cleanup         - Stop all services and clean up"
            echo "  clean           - Clean test results and reports"
            echo ""
            echo "For detailed options and examples, run: $0 --help"
        fi
        ;;
esac