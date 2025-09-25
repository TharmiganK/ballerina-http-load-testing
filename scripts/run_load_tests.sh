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
    log "Generating enhanced HTML reports with charts..."
    
    # Generate individual reports for each test by discovering existing results
    for csv_file in "${RESULTS_DIR}"/*.csv; do
        if [ -f "$csv_file" ]; then
            local test_name=$(basename "$csv_file" .csv)
            local h2load_file="${RESULTS_DIR}/${test_name}_h2load.txt"
            local report_dir="${REPORTS_DIR}/${test_name}"
            
            if [ -f "$h2load_file" ]; then
                info "Generating enhanced report for $test_name..."
                
                # Remove existing report directory
                if [ -d "$report_dir" ]; then
                    rm -rf "$report_dir"
                fi
                mkdir -p "$report_dir"
                
                # Generate enhanced HTML report from h2load output
                generate_enhanced_individual_report "$h2load_file" "$csv_file" "$report_dir" "$test_name"
                
                if [ $? -eq 0 ]; then
                    log "Enhanced report generated: $report_dir/index.html"
                else
                    warn "Failed to generate enhanced report for $test_name"
                fi
            fi
        fi
    done
    
    # Generate the main dashboard with comparisons
    generate_enhanced_dashboard_report
}

# Function to generate enhanced HTML report from h2load output with charts
generate_enhanced_individual_report() {
    local h2load_file="$1"
    local csv_file="$2"
    local report_dir="$3"
    local test_name="$4"
    
    local html_file="${report_dir}/index.html"
    
    # Extract metrics from CSV file (more accurate)
    local csv_data
    if [ -f "$csv_file" ]; then
        csv_data=$(tail -n 1 "$csv_file")
        IFS=',' read -r test_type total_requests duration_sec throughput_rps avg_latency_ms error_rate_percent <<< "$csv_data"
    else
        # Fallback to h2load file parsing
        total_requests=$(grep "requests:" "$h2load_file" | awk '{print $2}' || echo "0")
        throughput_rps=$(grep "req/s" "$h2load_file" | awk '{print $2}' || echo "0")
        avg_latency_ms="0"
        error_rate_percent="0"
        duration_sec="300"
    fi
    
    # Extract detailed metrics from h2load output
    local successful_requests=$(grep "status codes:" "$h2load_file" | awk '{print $3}' || echo "0")
    local failed_requests=$((total_requests - successful_requests))
    local min_latency=$(grep "time for request:" "$h2load_file" | awk '{print $2}' | sed 's/[^0-9.]//g' || echo "0")
    local max_latency=$(grep "time for request:" "$h2load_file" | awk '{print $4}' | sed 's/[^0-9.]//g' || echo "0")
    local p95_latency=$(grep "time for request:" "$h2load_file" | awk '{print $8}' | sed 's/[^0-9.]//g' || echo "0")
    
    # Parse service information
    local service_info=$(echo "$test_name" | cut -d'_' -f1)
    local payload_size=$(echo "$test_name" | cut -d'_' -f2)
    local user_count=$(echo "$test_name" | cut -d'_' -f3 | sed 's/users//')
    
    # Generate enhanced HTML report with Chart.js
    cat > "$html_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Enhanced Load Test Report - $test_name</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            background-color: #f5f7fa;
        }
        .header { 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            color: white; 
            padding: 30px; 
            text-align: center;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .header h1 { margin: 0; font-size: 2.5em; font-weight: 300; }
        .header h2 { margin: 10px 0 0 0; font-size: 1.2em; opacity: 0.9; }
        .header .test-info { margin: 15px 0 0 0; font-size: 1em; opacity: 0.8; }
        
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        
        .metrics-grid { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); 
            gap: 20px; 
            margin: 30px 0; 
        }
        .metric-card { 
            background: white; 
            padding: 25px; 
            border-radius: 12px; 
            text-align: center;
            box-shadow: 0 4px 6px rgba(0,0,0,0.05);
            border-left: 4px solid #667eea;
        }
        .metric-card h3 { margin: 0 0 15px 0; color: #4a5568; font-size: 0.9em; text-transform: uppercase; letter-spacing: 1px; }
        .metric-card .value { font-size: 2.5em; font-weight: 700; margin: 10px 0; }
        .metric-card .unit { font-size: 0.8em; color: #718096; margin-left: 5px; }
        .success { color: #48bb78; }
        .error { color: #f56565; }
        .primary { color: #667eea; }
        .warning { color: #ed8936; }
        
        .charts-section { margin: 40px 0; }
        .chart-container { 
            background: white; 
            padding: 30px; 
            border-radius: 12px; 
            margin: 20px 0;
            box-shadow: 0 4px 6px rgba(0,0,0,0.05);
        }
        .chart-container h3 { margin: 0 0 20px 0; color: #2d3748; }
        .chart-wrapper { height: 400px; position: relative; }
        
        .details-section {
            background: white;
            padding: 30px;
            border-radius: 12px;
            margin: 20px 0;
            box-shadow: 0 4px 6px rgba(0,0,0,0.05);
        }
        .details-section h3 { color: #2d3748; margin: 0 0 20px 0; }
        .raw-output { 
            background: #1a202c; 
            color: #e2e8f0; 
            padding: 20px; 
            border-radius: 8px; 
            overflow-x: auto; 
            font-family: 'Courier New', monospace; 
            font-size: 0.85em;
            line-height: 1.4;
        }
        
        .performance-indicators {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .indicator { 
            background: #f7fafc; 
            padding: 15px; 
            border-radius: 8px; 
            text-align: center;
            border: 1px solid #e2e8f0;
        }
        .indicator h4 { margin: 0 0 10px 0; color: #4a5568; font-size: 0.8em; }
        .indicator .indicator-value { font-weight: 600; font-size: 1.2em; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Load Test Report</h1>
        <h2>$test_name</h2>
        <div class="test-info">
            Service: <strong>$service_info</strong> | 
            Payload: <strong>$payload_size</strong> | 
            Users: <strong>$user_count</strong> | 
            Duration: <strong>${duration_sec}s</strong>
        </div>
        <div class="test-info">Generated on: $(date)</div>
    </div>
    
    <div class="container">
        <!-- Key Metrics -->
        <div class="metrics-grid">
            <div class="metric-card">
                <h3>Total Requests</h3>
                <div class="value primary">$(printf "%'d" $total_requests)</div>
            </div>
            <div class="metric-card">
                <h3>Successful Requests</h3>
                <div class="value success">$(printf "%'d" $successful_requests)</div>
            </div>
            <div class="metric-card">
                <h3>Failed Requests</h3>
                <div class="value error">$(printf "%'d" $failed_requests)</div>
            </div>
            <div class="metric-card">
                <h3>Throughput</h3>
                <div class="value primary">$throughput_rps<span class="unit">req/s</span></div>
            </div>
            <div class="metric-card">
                <h3>Average Latency</h3>
                <div class="value warning">$avg_latency_ms<span class="unit">ms</span></div>
            </div>
            <div class="metric-card">
                <h3>Error Rate</h3>
                <div class="value $([ ${error_rate_percent%.*} -eq 0 ] && echo "success" || echo "error")">$error_rate_percent<span class="unit">%</span></div>
            </div>
        </div>
        
        <!-- Performance Indicators -->
        <div class="charts-section">
            <div class="chart-container">
                <h3>Performance Overview</h3>
                <div class="performance-indicators">
                    <div class="indicator">
                        <h4>Min Latency</h4>
                        <div class="indicator-value success">$min_latency ms</div>
                    </div>
                    <div class="indicator">
                        <h4>Avg Latency</h4>
                        <div class="indicator-value primary">$avg_latency_ms ms</div>
                    </div>
                    <div class="indicator">
                        <h4>Max Latency</h4>
                        <div class="indicator-value warning">$max_latency ms</div>
                    </div>
                    <div class="indicator">
                        <h4>95th Percentile</h4>
                        <div class="indicator-value">$p95_latency ms</div>
                    </div>
                </div>
            </div>
            
            <!-- Request Distribution Chart -->
            <div class="chart-container">
                <h3>Request Status Distribution</h3>
                <div class="chart-wrapper">
                    <canvas id="statusChart"></canvas>
                </div>
            </div>
            
            <!-- Performance Metrics Chart -->
            <div class="chart-container">
                <h3>Performance Metrics</h3>
                <div class="chart-wrapper">
                    <canvas id="metricsChart"></canvas>
                </div>
            </div>
        </div>
        
        <!-- Raw Output -->
        <div class="details-section">
            <h3>Raw h2load Output</h3>
            <div class="raw-output">$(cat "$h2load_file" | sed 's/</\&lt;/g' | sed 's/>/\&gt;/g')</div>
        </div>
        
        <!-- CSV Data -->
        <div class="details-section">
            <h3>CSV Results</h3>
            <div class="raw-output">$(cat "$csv_file" | sed 's/</\&lt;/g' | sed 's/>/\&gt;/g')</div>
        </div>
    </div>
    
    <script>
        // Request Status Distribution Chart
        const statusCtx = document.getElementById('statusChart').getContext('2d');
        new Chart(statusCtx, {
            type: 'doughnut',
            data: {
                labels: ['Successful', 'Failed'],
                datasets: [{
                    data: [$successful_requests, $failed_requests],
                    backgroundColor: ['#48bb78', '#f56565'],
                    borderWidth: 0
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels: {
                            padding: 20,
                            font: { size: 14 }
                        }
                    }
                }
            }
        });
        
        // Performance Metrics Chart
        const metricsCtx = document.getElementById('metricsChart').getContext('2d');
        new Chart(metricsCtx, {
            type: 'bar',
            data: {
                labels: ['Min Latency', 'Avg Latency', 'Max Latency', '95th Percentile'],
                datasets: [{
                    label: 'Latency (ms)',
                    data: [$min_latency, $avg_latency_ms, $max_latency, $p95_latency],
                    backgroundColor: ['#48bb78', '#667eea', '#f56565', '#ed8936'],
                    borderRadius: 6,
                    borderWidth: 0
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Latency (ms)'
                        }
                    }
                }
            }
        });
    </script>
</body>
</html>
EOF
    
    return 0
}

# Function to generate enhanced dashboard report with comparison charts
generate_enhanced_dashboard_report() {
    log "Creating enhanced dashboard report with comparison charts..."
    
    local dashboard_file="${REPORTS_DIR}/dashboard.html"
    
    # Collect all CSV data for analysis by discovering existing files
    local all_results=()
    local services_tested=()
    local file_sizes_tested=()
    local users_tested=()
    
    # Discover all CSV files in results directory
    for csv_file in "${RESULTS_DIR}"/*.csv; do
        if [ -f "$csv_file" ]; then
            local csv_data=$(tail -n 1 "$csv_file")
            all_results+=("$csv_data")
            
            # Extract service, file_size, and users from filename
            local filename=$(basename "$csv_file" .csv)
            # Parse filename format: service_filesize_usersusers
            # Service names can have dashes and possibly 'c' suffixes
            if [[ $filename =~ ^(h[12]c?-h[12]c?)_([^_]+)_([0-9]+)users$ ]]; then
                local service="${BASH_REMATCH[1]}"
                local file_size="${BASH_REMATCH[2]}"
                local users="${BASH_REMATCH[3]}"
                
                # Add to unique arrays
                if [[ ! " ${services_tested[@]} " =~ " ${service} " ]]; then
                    services_tested+=("$service")
                fi
                if [[ ! " ${file_sizes_tested[@]} " =~ " ${file_size} " ]]; then
                    file_sizes_tested+=("$file_size")
                fi
                if [[ ! " ${users_tested[@]} " =~ " ${users} " ]]; then
                    users_tested+=("$users")
                fi
            fi
        fi
    done
    
    # Generate comprehensive dashboard
    cat > "$dashboard_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Ballerina HTTP Load Testing Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            background-color: #f8f9fa;
        }
        .header { 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            color: white; 
            padding: 40px; 
            text-align: center;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .header h1 { margin: 0; font-size: 3em; font-weight: 300; }
        .header p { margin: 15px 0 0 0; font-size: 1.1em; opacity: 0.9; }
        
        .container { max-width: 1600px; margin: 0 auto; padding: 30px; }
        
        .summary-grid { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); 
            gap: 25px; 
            margin: 40px 0; 
        }
        .summary-card { 
            background: white; 
            padding: 30px; 
            border-radius: 15px; 
            box-shadow: 0 8px 25px rgba(0,0,0,0.08);
            border-left: 5px solid #667eea;
        }
        .summary-card h3 { margin: 0 0 20px 0; color: #2d3748; font-size: 1.2em; }
        .summary-card ul { margin: 0; padding: 0; list-style: none; }
        .summary-card li { margin: 8px 0; padding: 8px 0; color: #4a5568; }
        .summary-card .highlight { font-weight: 600; color: #667eea; }
        
        .charts-section { margin: 50px 0; }
        .chart-row { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(500px, 1fr)); 
            gap: 30px; 
            margin: 30px 0; 
        }
        .chart-container { 
            background: white; 
            padding: 30px; 
            border-radius: 15px; 
            box-shadow: 0 8px 25px rgba(0,0,0,0.08);
        }
        .chart-container h3 { 
            margin: 0 0 25px 0; 
            color: #2d3748; 
            font-size: 1.3em; 
            text-align: center;
        }
        .chart-wrapper { height: 400px; position: relative; }
        .chart-wrapper-large { height: 500px; position: relative; }
        
        .filter-section {
            background: white;
            padding: 25px;
            border-radius: 15px;
            margin: 20px 0;
            box-shadow: 0 8px 25px rgba(0,0,0,0.08);
        }
        .filter-controls {
            display: flex;
            flex-wrap: wrap;
            gap: 15px;
            align-items: center;
        }
        .filter-controls label {
            color: #4a5568;
            font-weight: 600;
        }
        .filter-controls select {
            padding: 8px 12px;
            border: 2px solid #e2e8f0;
            border-radius: 6px;
            background: white;
            color: #2d3748;
        }
        
        .protocol-comparison {
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            color: white;
            padding: 30px;
            border-radius: 15px;
            margin: 30px 0;
            text-align: center;
        }
        .protocol-comparison h3 { margin: 0 0 15px 0; }
        
        .results-table {
            background: white;
            padding: 30px;
            border-radius: 15px;
            margin: 30px 0;
            box-shadow: 0 8px 25px rgba(0,0,0,0.08);
            overflow-x: auto;
        }
        .results-table table {
            width: 100%;
            border-collapse: collapse;
        }
        .results-table th, .results-table td {
            padding: 12px 15px;
            text-align: left;
            border-bottom: 1px solid #e2e8f0;
        }
        .results-table th {
            background-color: #f7fafc;
            font-weight: 600;
            color: #2d3748;
        }
        .results-table tr:hover {
            background-color: #f7fafc;
        }
        .service-h1 { color: #38a169; }
        .service-h2 { color: #3182ce; }
        .performance-good { color: #38a169; font-weight: 600; }
        .performance-average { color: #d69e2e; font-weight: 600; }
        .performance-poor { color: #e53e3e; font-weight: 600; }
    </style>
</head>
<body>
        <div class="header">
        <h1>🚀 Ballerina HTTP Load Testing Dashboard</h1>
        <p>Performance Analysis - Service Configuration Results</p>
        <p>Generated on: $(date)</p>
    </div>
    
    <div class="container">
        <!-- Test Summary -->
        <div class="summary-grid">
            <div class="summary-card">
                <h3>📊 Test Overview</h3>
                <ul>
EOF

    # Add dynamic content based on actual test results
    echo "                    <li>Services Tested: <span class=\"highlight\">${#services_tested[@]}</span></li>" >> "$dashboard_file"
    echo "                    <li>Payload Sizes: <span class=\"highlight\">${#file_sizes_tested[@]}</span> ($(IFS=', '; echo "${file_sizes_tested[*]}"))</li>" >> "$dashboard_file"
    echo "                    <li>User Loads: <span class=\"highlight\">${#users_tested[@]}</span> ($(IFS=', '; echo "${users_tested[*]}"))</li>" >> "$dashboard_file"
    echo "                    <li>Total Tests: <span class=\"highlight\">${#all_results[@]}</span></li>" >> "$dashboard_file"
    echo "                    <li>Duration: <span class=\"highlight\">${TEST_DURATION}s each</span></li>" >> "$dashboard_file"

    cat >> "$dashboard_file" << 'EOF'
                </ul>
            </div>
            <div class="summary-card">
                <h3>🔧 Service Configurations</h3>
                <ul>
                    <li>🟢 <strong>HTTP/1.1:</strong> h1-h1, h1c-h1, h1-h1c, h1c-h1c</li>
                    <li>🔵 <strong>HTTP/2:</strong> h2-h2, h2c-h2, h2-h2c, h2c-h2c</li>
                    <li>🔄 <strong>Mixed H1→H2:</strong> h1-h2, h1c-h2, h1-h2c, h1c-h2c</li>
                    <li>🔄 <strong>Mixed H2→H1:</strong> h2-h1, h2c-h1, h2-h1c, h2c-h1c</li>
                </ul>
            </div>
            <div class="summary-card">
                <h3>📈 Performance Summary</h3>
                <ul id="performance-summary">
                    <!-- Will be populated by JavaScript -->
                </ul>
            </div>
        </div>
        
        <!-- Service Performance Analysis -->
        <div class="service-analysis">
            <h3>Service Performance Analysis</h3>
            <p>Analyze performance across different service configurations, payload sizes, and concurrent user loads</p>
        </div>
        
        <!-- Charts Section -->
        <div class="charts-section charts-container">
            <!-- Main Performance Charts -->
            <div class="chart-row">
                <div class="chart-container">
                    <h3>📊 Throughput by Service & Payload</h3>
                    <div class="chart-wrapper">
                        <canvas id="serviceChart"></canvas>
                    </div>
                </div>
                <div class="chart-container">
                    <h3>⚡ Latency by Service & Payload</h3>
                    <div class="chart-wrapper">
                        <canvas id="latencyChart"></canvas>
                    </div>
                </div>
            </div>
            
            <!-- Performance Matrix for Detailed Analysis -->
            <div class="chart-container">
                <h3>🎯 Performance Matrix - Throughput vs Latency</h3>
                <div class="chart-wrapper-large">
                    <canvas id="matrixChart"></canvas>
                </div>
            </div>
        </div>
        
        <!-- Detailed Results Table -->
        <div class="results-table">
            <h3>📋 Detailed Test Results</h3>
            <table id="resultsTable">
                <thead>
                    <tr>
                        <th>Service</th>
                        <th>Payload</th>
                        <th>Users</th>
                        <th>Throughput (req/s)</th>
                        <th>Avg Latency (ms)</th>
                        <th>Error Rate (%)</th>
                        <th>Total Requests</th>
                        <th>Report</th>
                    </tr>
                </thead>
                <tbody id="resultsTableBody">
                    <!-- Will be populated by JavaScript -->
                </tbody>
            </table>
        </div>
    </div>
    
    <script>
        // Test results data
        const testResults = [
EOF

    # Add JavaScript data from CSV results
    local first_result=true
    for result in "${all_results[@]}"; do
        if [ "$first_result" = false ]; then
            echo "," >> "$dashboard_file"
        fi
        first_result=false
        IFS=',' read -r test_type total_requests duration_sec throughput_rps avg_latency_ms error_rate_percent <<< "$result"
        IFS='_' read -r service payload users_str <<< "$test_type"
        users=$(echo "$users_str" | sed 's/users//')
        
        echo "            {" >> "$dashboard_file"
        echo "                service: '$service'," >> "$dashboard_file"
        echo "                payload: '$payload'," >> "$dashboard_file"
        echo "                users: $users," >> "$dashboard_file"
        echo "                throughput: $throughput_rps," >> "$dashboard_file"
        echo "                latency: $avg_latency_ms," >> "$dashboard_file"
        echo "                errorRate: $error_rate_percent," >> "$dashboard_file"
        echo "                totalRequests: $total_requests," >> "$dashboard_file"
        echo "                testName: '$test_type'" >> "$dashboard_file"
        echo "            }" >> "$dashboard_file"
    done

    cat >> "$dashboard_file" << 'EOF'
        ];
        
        // Process data for charts
        const services = [...new Set(testResults.map(r => r.service))];
        const payloads = [...new Set(testResults.map(r => r.payload))];
        const userCounts = [...new Set(testResults.map(r => r.users))].sort((a,b) => a-b);
        
        // Color schemes
        const serviceColors = {
            'h1-h1': '#48bb78', 'h1c-h1': '#38a169', 'h1-h1c': '#2f855a', 'h1c-h1c': '#276749',
            'h2-h2': '#4299e1', 'h2c-h2': '#3182ce', 'h2-h2c': '#2b77cb', 'h2c-h2c': '#2c5aa0',
            'h1-h2': '#ed8936', 'h1c-h2': '#dd6b20', 'h1-h2c': '#c05621', 'h1c-h2c': '#9c4221',
            'h2-h1': '#9f7aea', 'h2c-h1': '#805ad5', 'h2-h1c': '#6b46c1', 'h2c-h1c': '#553c9a'
        };
        
        // Generate insights
        function generateInsights() {
            const insights = document.getElementById('performance-summary');
            const avgThroughput = testResults.reduce((sum, r) => sum + r.throughput, 0) / testResults.length;
            const bestService = testResults.reduce((best, r) => r.throughput > best.throughput ? r : best);
            const totalRequests = testResults.reduce((sum, r) => sum + r.totalRequests, 0);
            const avgLatency = testResults.reduce((sum, r) => sum + r.latency, 0) / testResults.length;
            
            insights.innerHTML = `
                <li>Average Throughput: <span class="highlight">${Math.round(avgThroughput)} req/s</span></li>
                <li>Best Performing Service: <span class="highlight">${bestService.service}</span> (${Math.round(bestService.throughput)} req/s)</li>
                <li>Average Latency: <span class="highlight">${avgLatency.toFixed(2)} ms</span></li>
                <li>Total Requests Processed: <span class="highlight">${totalRequests.toLocaleString()}</span></li>
                <li>Services Tested: <span class="highlight">${services.length}</span></li>
            `;
        }
        
        // Interactive Throughput Chart (Grouped by Service with Payload breakdown)
        function createServiceChart() {
            const ctx = document.getElementById('serviceChart').getContext('2d');
            
            // Create datasets for each payload size
            const datasets = payloads.map((payload, index) => {
                const data = services.map(service => {
                    const results = testResults.filter(r => r.service === service && r.payload === payload);
                    return results.length > 0 ? results.reduce((sum, r) => sum + r.throughput, 0) / results.length : 0;
                });
                
                const hue = index * (360 / payloads.length);
                return {
                    label: payload,
                    data: data,
                    backgroundColor: 'hsla(' + hue + ', 70%, 60%, 0.8)',
                    borderColor: 'hsl(' + hue + ', 70%, 50%)',
                    borderWidth: 2,
                    borderRadius: 4
                };
            });
            
            window.serviceChart = new Chart(ctx, {
                type: 'bar',
                data: {
                    labels: services,
                    datasets: datasets
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: {
                        mode: 'index',
                        intersect: false
                    },
                    plugins: {
                        legend: { 
                            display: true,
                            position: 'top',
                            labels: {
                                usePointStyle: true,
                                padding: 15
                            }
                        },
                        tooltip: {
                            callbacks: {
                                label: function(context) {
                                    return context.dataset.label + ': ' + Math.round(context.parsed.y).toLocaleString() + ' req/s';
                                }
                            }
                        }
                    },
                    scales: {
                        y: {
                            beginAtZero: true,
                            title: { display: true, text: 'Throughput (req/s)', font: { size: 14, weight: 'bold' } }
                        },
                        x: {
                            title: { display: true, text: 'Service Configuration', font: { size: 14, weight: 'bold' } }
                        }
                    },
                    animation: {
                        duration: 1000,
                        easing: 'easeInOutQuart'
                    }
                }
            });
        }
        
        // Interactive Latency Chart (Grouped by Service with Payload breakdown)  
        function createLatencyChart() {
            const ctx = document.getElementById('latencyChart').getContext('2d');
            
            // Create datasets for each payload size
            const datasets = payloads.map((payload, index) => {
                const data = services.map(service => {
                    const results = testResults.filter(r => r.service === service && r.payload === payload);
                    return results.length > 0 ? results.reduce((sum, r) => sum + r.latency, 0) / results.length : 0;
                });
                
                const hue = index * (360 / payloads.length);
                return {
                    label: payload,
                    data: data,
                    backgroundColor: 'hsla(' + hue + ', 70%, 60%, 0.8)',
                    borderColor: 'hsl(' + hue + ', 70%, 50%)',
                    borderWidth: 2,
                    borderRadius: 4
                };
            });
            
            window.latencyChart = new Chart(ctx, {
                type: 'bar',
                data: {
                    labels: services,
                    datasets: datasets
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: {
                        mode: 'index',
                        intersect: false
                    },
                    plugins: {
                        legend: { 
                            display: true,
                            position: 'top',
                            labels: {
                                usePointStyle: true,
                                padding: 15
                            }
                        },
                        tooltip: {
                            callbacks: {
                                label: function(context) {
                                    return context.dataset.label + ': ' + context.parsed.y.toFixed(2) + ' ms';
                                }
                            }
                        }
                    },
                    scales: {
                        y: {
                            beginAtZero: true,
                            title: { display: true, text: 'Average Latency (ms)', font: { size: 14, weight: 'bold' } }
                        },
                        x: {
                            title: { display: true, text: 'Service Configuration', font: { size: 14, weight: 'bold' } }
                        }
                    },
                    animation: {
                        duration: 1000,
                        easing: 'easeInOutQuart'
                    }
                }
            });
        }
        
        // Interactive Filtering Functions
        function updateCharts() {
            const selectedPayloads = Array.from(document.querySelectorAll('input[name="payload"]:checked')).map(cb => cb.value);
            const selectedUsers = Array.from(document.querySelectorAll('input[name="users"]:checked')).map(cb => parseInt(cb.value));
            
            // Filter test results
            let filteredResults = testResults;
            if (selectedPayloads.length > 0) {
                filteredResults = filteredResults.filter(r => selectedPayloads.includes(r.payload));
            }
            if (selectedUsers.length > 0) {
                filteredResults = filteredResults.filter(r => selectedUsers.includes(r.users));
            }
            
            // Update service chart
            updateServiceChart(filteredResults, selectedPayloads.length > 0 ? selectedPayloads : payloads);
            updateLatencyChart(filteredResults, selectedPayloads.length > 0 ? selectedPayloads : payloads);
            updateResultsTable(filteredResults);
        }
        
        function updateServiceChart(filteredResults, activePayloads) {
            if (!window.serviceChart) return;
            
            const datasets = activePayloads.map((payload, index) => {
                const data = services.map(service => {
                    const results = filteredResults.filter(r => r.service === service && r.payload === payload);
                    return results.length > 0 ? results.reduce((sum, r) => sum + r.throughput, 0) / results.length : 0;
                });
                
                const hue = index * (360 / activePayloads.length);
                return {
                    label: payload,
                    data: data,
                    backgroundColor: 'hsla(' + hue + ', 70%, 60%, 0.8)',
                    borderColor: 'hsl(' + hue + ', 70%, 50%)',
                    borderWidth: 2,
                    borderRadius: 4
                };
            });
            
            window.serviceChart.data.datasets = datasets;
            window.serviceChart.update('active');
        }
        
        function updateLatencyChart(filteredResults, activePayloads) {
            if (!window.latencyChart) return;
            
            const datasets = activePayloads.map((payload, index) => {
                const data = services.map(service => {
                    const results = filteredResults.filter(r => r.service === service && r.payload === payload);
                    return results.length > 0 ? results.reduce((sum, r) => sum + r.latency, 0) / results.length : 0;
                });
                
                const hue = index * (360 / activePayloads.length);
                return {
                    label: payload,
                    data: data,
                    backgroundColor: 'hsla(' + hue + ', 70%, 60%, 0.8)',
                    borderColor: 'hsl(' + hue + ', 70%, 50%)',
                    borderWidth: 2,
                    borderRadius: 4
                };
            });
            
            window.latencyChart.data.datasets = datasets;
            window.latencyChart.update('active');
        }
        
        function updateResultsTable(filteredResults) {
            const tbody = document.getElementById('resultsTableBody');
            tbody.innerHTML = filteredResults.map(result => {
                const performanceClass = result.throughput > 15000 ? 'performance-good' : 
                                       result.throughput > 10000 ? 'performance-average' : 'performance-poor';
                const serviceClass = result.service.startsWith('h2') ? 'service-h2' : 'service-h1';
                
                return '<tr>' +
                    '<td class="' + serviceClass + '">' + result.service + '</td>' +
                    '<td>' + result.payload + '</td>' +
                    '<td>' + result.users + '</td>' +
                    '<td class="' + performanceClass + '">' + Math.round(result.throughput) + '</td>' +
                    '<td>' + result.latency + '</td>' +
                    '<td>' + result.errorRate + '</td>' +
                    '<td>' + result.totalRequests.toLocaleString() + '</td>' +
                    '<td><a href="' + result.testName + '/index.html" target="_blank">View Details</a></td>' +
                '</tr>';
            }).join('');
        }
        
        // Create Interactive Filter Controls
        function createFilterControls() {
            const payloadFilters = payloads.map(payload => 
                '<label style="display: block; margin-bottom: 8px; cursor: pointer;">' +
                    '<input type="checkbox" name="payload" value="' + payload + '" checked style="margin-right: 8px;">' +
                    '<span style="font-weight: 500;">' + payload + '</span>' +
                '</label>'
            ).join('');
            
            const userFilters = userCounts.map(users => 
                '<label style="display: block; margin-bottom: 8px; cursor: pointer;">' +
                    '<input type="checkbox" name="users" value="' + users + '" checked style="margin-right: 8px;">' +
                    '<span style="font-weight: 500;">' + users + ' users</span>' +
                '</label>'
            ).join('');
            
            const filterHtml = '<div class="filter-controls" style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 30px;">' +
                '<h3 style="margin-top: 0; color: #2d3748;">🔍 Interactive Filters</h3>' +
                '<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 30px;">' +
                    '<div>' +
                        '<h4 style="margin-bottom: 15px; color: #4a5568;">Payload Sizes</h4>' +
                        payloadFilters +
                    '</div>' +
                    '<div>' +
                        '<h4 style="margin-bottom: 15px; color: #4a5568;">Concurrent Users</h4>' +
                        userFilters +
                    '</div>' +
                '</div>' +
                '<div style="margin-top: 20px;">' +
                    '<button onclick="selectAllFilters()" style="background: #667eea; color: white; border: none; padding: 8px 16px; border-radius: 4px; margin-right: 10px; cursor: pointer;">Select All</button>' +
                    '<button onclick="clearAllFilters()" style="background: #e53e3e; color: white; border: none; padding: 8px 16px; border-radius: 4px; cursor: pointer;">Clear All</button>' +
                '</div>' +
            '</div>';
            
            const chartsContainer = document.querySelector('.charts-container');
            chartsContainer.insertAdjacentHTML('afterbegin', filterHtml);
            
            // Add event listeners
            document.querySelectorAll('input[name="payload"], input[name="users"]').forEach(checkbox => {
                checkbox.addEventListener('change', updateCharts);
            });
        }
        
        function selectAllFilters() {
            document.querySelectorAll('input[name="payload"], input[name="users"]').forEach(cb => cb.checked = true);
            updateCharts();
        }
        
        function clearAllFilters() {
            document.querySelectorAll('input[name="payload"], input[name="users"]').forEach(cb => cb.checked = false);
            updateCharts();
        }
        
        // Performance Matrix Chart
        function createMatrixChart() {
            const ctx = document.getElementById('matrixChart').getContext('2d');
            
            new Chart(ctx, {
                type: 'scatter',
                data: {
                    datasets: services.map(service => ({
                        label: service,
                        data: testResults.filter(r => r.service === service).map(r => ({
                            x: r.throughput,
                            y: r.latency,
                            payload: r.payload,
                            users: r.users
                        })),
                        backgroundColor: serviceColors[service] || '#667eea',
                        pointRadius: 8,
                        pointHoverRadius: 12
                    }))
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: { 
                            display: true,
                            position: 'top'
                        },
                        tooltip: {
                            callbacks: {
                                label: function(context) {
                                    return context.dataset.label + ': ' + Math.round(context.parsed.x) + ' req/s, ' + context.parsed.y + 'ms (' + context.raw.payload + ', ' + context.raw.users + ' users)';
                                }
                            }
                        }
                    },
                    scales: {
                        x: {
                            title: { display: true, text: 'Throughput (req/s)' }
                        },
                        y: {
                            title: { display: true, text: 'Average Latency (ms)' }
                        }
                    }
                }
            });
        }
        
        // Populate results table
        function populateResultsTable() {
            const tbody = document.getElementById('resultsTableBody');
            tbody.innerHTML = testResults.map(result => {
                const performanceClass = result.throughput > 15000 ? 'performance-good' : 
                                       result.throughput > 10000 ? 'performance-average' : 'performance-poor';
                const serviceClass = result.service.startsWith('h2') ? 'service-h2' : 'service-h1';
                
                return '<tr>' +
                    '<td class="' + serviceClass + '">' + result.service + '</td>' +
                    '<td>' + result.payload + '</td>' +
                    '<td>' + result.users + '</td>' +
                    '<td class="' + performanceClass + '">' + Math.round(result.throughput) + '</td>' +
                    '<td>' + result.latency + '</td>' +
                    '<td>' + result.errorRate + '</td>' +
                    '<td>' + result.totalRequests.toLocaleString() + '</td>' +
                    '<td><a href="' + result.testName + '/index.html" target="_blank">View Details</a></td>' +
                '</tr>';
            }).join('');
        }
        
        // Initialize dashboard
        document.addEventListener('DOMContentLoaded', function() {
            console.log('Dashboard loading...', testResults.length, 'test results found');
            console.log('Services:', services);
            console.log('Payloads:', payloads);
            console.log('User counts:', userCounts);
            
            try {
                generateInsights();
                console.log('Insights generated');
            } catch (e) {
                console.error('Error generating insights:', e);
            }
            
            try {
                createFilterControls();
                console.log('Filter controls created');
            } catch (e) {
                console.error('Error creating filter controls:', e);
            }
            
            try {
                createServiceChart();
                console.log('Service chart created');
            } catch (e) {
                console.error('Error creating service chart:', e);
            }
            
            try {
                createLatencyChart();
                console.log('Latency chart created');
            } catch (e) {
                console.error('Error creating latency chart:', e);
            }
            
            try {
                createMatrixChart();
                console.log('Matrix chart created');
            } catch (e) {
                console.error('Error creating matrix chart:', e);
            }
            
            try {
                populateResultsTable();
                console.log('Results table populated');
            } catch (e) {
                console.error('Error populating results table:', e);
            }
        });
    </script>
</body>
</html>
EOF
    
    log "Enhanced dashboard report created: $dashboard_file"
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
    generate_enhanced_dashboard_report
    
    log "Load testing completed successfully!"
    log "Results available in: $RESULTS_DIR"
    log "HTML reports available in: $REPORTS_DIR"
    log "📊 Enhanced Dashboard: $REPORTS_DIR/dashboard.html"
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