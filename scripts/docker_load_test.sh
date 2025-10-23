#!/bin/bash

# Dockerized Ballerina HTTP Load Testing with CPU Isolation
# Provides consistent, repeatable results with statistical analysis

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="${PROJECT_ROOT}/docker-results"
DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/docker/docker-compose.yml"

# Enhanced test parameters for consistency
WARMUP_DURATION=300     # 5 minutes warmup
TEST_DURATION=900       # 15 minutes test
COOLDOWN_DURATION=60    # 1 minute cooldown between runs
NUM_RUNS=5              # Number of statistical runs
DISCARD_FIRST_RUN=true  # Discard first run (warmup)

# Reduced concurrent users to prevent CPU oversaturation
DEFAULT_CONCURRENT_USERS=(100)  # Reduced from 200 to prevent >90% CPU usage

# Default test configurations
DEFAULT_FILE_SIZES=("1KB" "10KB" "100KB")
DEFAULT_SERVICES=("h1c-h1c" "h2c-h2c" "h1c-h2c")  # Representative subset for CPU isolation testing

# Current test parameters
CONCURRENT_USERS=()
FILE_SIZES=()
SERVICES=()

# CPU monitoring configuration
CPU_MONITOR_INTERVAL=5  # Monitor CPU every 5 seconds
MAX_CPU_THRESHOLD=90    # Alert if CPU > 90%

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Function to check CPU core availability
check_cpu_cores() {
    local required_cores=8
    local system_cores=$(nproc)
    
    # Check Docker's available CPUs which may be less than system CPUs
    local docker_cores=$(docker system info --format '{{.NCPU}}' 2>/dev/null || echo "$system_cores")
    local available_cores=$docker_cores
    
    if [ "$available_cores" -lt "$required_cores" ]; then
        warn "Docker has $available_cores CPUs available (system: $system_cores)"
        warn "Adjusting CPU allocation to available cores..."
        
        # Adjust CPU allocation based on available cores
        if [ "$available_cores" -ge 6 ]; then
            PASSTHROUGH_CORES="0,1"
            BACKEND_CORES="2,3"
            H2LOAD_CORES="4,5"
            log "✅ CPU allocation: Passthrough(0-1), Backend(2-3), h2load(4-5)"
        elif [ "$available_cores" -ge 4 ]; then
            PASSTHROUGH_CORES="0"
            BACKEND_CORES="1"
            H2LOAD_CORES="2,3"
            log "✅ CPU allocation: Passthrough(0), Backend(1), h2load(2-3)"
        else
            error "Minimum 4 cores required for proper isolation. Available: $available_cores"
            exit 1
        fi
    else
        PASSTHROUGH_CORES="0,1"
        BACKEND_CORES="2,3"
        H2LOAD_CORES="4,5,6,7"
        log "✅ CPU allocation: Passthrough(0-1), Backend(2-3), h2load(4-7)"
    fi
}

# Function to configure services based on service name
configure_services() {
    local service_name=$1
    
    # Service configuration arrays (matching quick_test.sh)
    local SERVICE_NAMES=("h1-h1" "h1c-h1" "h1-h1c" "h1c-h1c" "h2-h2" "h2c-h2" "h2-h2c" "h2c-h2c" "h1-h2" "h1c-h2" "h1-h2c" "h1c-h2c" "h2-h1" "h2c-h1" "h2-h1c" "h2c-h1c")
    local SERVICE_PORTS=(9091 9092 9093 9094 9095 9096 9097 9098 9099 9100 9101 9102 9103 9104 9105 9106)
    local SERVICE_CLIENT_SSL=(true true false false true true false false true true false false true true false false)
    local SERVICE_SERVER_SSL=(true false true false true false true false true false true false true false true false)
    local SERVICE_CLIENT_HTTP2=(false false false false true true true true false false false false true true true true)
    local SERVICE_SERVER_HTTP2=(false false false false true true true true false false false false false false false false)
    local SERVICE_BACKEND_SSL=(true true false false true true false false true true false false true true false false)
    local SERVICE_BACKEND_HTTP2=(false false false false true true true true true true true true false false false false)
    local SERVICE_BACKEND_PORTS=(8689 8700 8688 8701 8691 8702 8690 8703 8693 8704 8692 8705 8706 8707 8708 8709)
    
    # Find service index
    local service_index=-1
    for i in "${!SERVICE_NAMES[@]}"; do
        if [ "${SERVICE_NAMES[$i]}" = "$service_name" ]; then
            service_index=$i
            break
        fi
    done
    
    if [ $service_index -eq -1 ]; then
        error "Unknown service: $service_name"
        log "Available services: ${SERVICE_NAMES[*]}"
        exit 1
    fi
    
    # Export configuration as environment variables for Docker Compose
    export CLIENT_SSL=${SERVICE_CLIENT_SSL[$service_index]}
    export SERVER_SSL=${SERVICE_SERVER_SSL[$service_index]}
    export CLIENT_HTTP2=${SERVICE_CLIENT_HTTP2[$service_index]}
    export SERVER_HTTP2=${SERVICE_SERVER_HTTP2[$service_index]}
    export SERVER_PORT=${SERVICE_PORTS[$service_index]}
    export BACKEND_PORT=${SERVICE_BACKEND_PORTS[$service_index]}
    export BACKEND_SSL=${SERVICE_BACKEND_SSL[$service_index]}
    export BACKEND_HTTP2=${SERVICE_BACKEND_HTTP2[$service_index]}
    
    log "🔧 Configured service: $service_name"
    log "   Passthrough: Port $SERVER_PORT, SSL=$SERVER_SSL, HTTP2=$SERVER_HTTP2"
    log "   Backend: Port $BACKEND_PORT, SSL=$BACKEND_SSL, HTTP2=$BACKEND_HTTP2"
    log "   Client: SSL=$CLIENT_SSL, HTTP2=$CLIENT_HTTP2"
}

# Function to monitor CPU usage
monitor_cpu_usage() {
    local duration=$1
    local output_file="$2"
    
    log "Monitoring CPU usage for ${duration}s..."
    
    {
        echo "timestamp,cpu_user,cpu_system,cpu_idle,cpu_total"
        
        for ((i=0; i<duration; i+=CPU_MONITOR_INTERVAL)); do
            local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
            # Use top command for macOS compatibility instead of sar
            local cpu_idle=$(top -l 1 -n 0 | grep "CPU usage" | awk '{print $7}' | sed 's/%//')
            if [[ -z "$cpu_idle" ]]; then
                # Fallback if top format is different
                cpu_idle="0.0"
            fi
            local cpu_total=$(echo "100 - ${cpu_idle}" | bc -l 2>/dev/null || echo "100")
            
            echo "$timestamp,$cpu_stats,$cpu_total"
            
            # Alert if CPU usage too high
            if (( $(echo "$cpu_total > $MAX_CPU_THRESHOLD" | bc -l) )); then
                warn "⚠️  High CPU usage detected: ${cpu_total}% (threshold: ${MAX_CPU_THRESHOLD}%)"
            fi
        done
    } > "$output_file"
}

# Function to build Docker images
build_docker_images() {
    log "🔨 Building Docker images..."
    
    # Build projects first
    log "Building Ballerina project..."
    cd "$PROJECT_ROOT/ballerina-passthrough"
    bal build
    
    log "Building Netty backend..."
    cd "$PROJECT_ROOT/netty-backend"
    mvn clean package -q
    
    # Build Docker images
    cd "$PROJECT_ROOT"
    log "Building Docker images with resource constraints..."
    
    docker compose -f "$DOCKER_COMPOSE_FILE" build --parallel
    
    if [ $? -eq 0 ]; then
        log "✅ Docker images built successfully"
    else
        error "Failed to build Docker images"
        exit 1
    fi
}

# Function to start services with resource isolation
start_services() {
    local service_name=$1
    
    log "🚀 Starting containerized services with CPU isolation..."
    
    # Configure service parameters before starting
    configure_services "$service_name"
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    
    # Start backend service first
    log "Starting Netty backend (CPU cores $BACKEND_CORES)..."
    docker compose -f "$DOCKER_COMPOSE_FILE" up -d backend
    
    # Start passthrough service
    log "Starting Ballerina passthrough (CPU cores $PASSTHROUGH_CORES)..."  
    docker compose -f "$DOCKER_COMPOSE_FILE" up -d passthrough
    
    # Wait for services to start
    log "Waiting for services to initialize..."
    sleep 10
    
    # Apply CPU constraints manually using docker update
    log "Applying CPU core constraints..."
    
    # Pin backend to cores 2-3
    if docker ps --format "table {{.Names}}" | grep -q "netty-backend"; then
        docker update --cpuset-cpus="$BACKEND_CORES" netty-backend
        log "✅ Backend pinned to CPU cores $BACKEND_CORES"
    fi
    
    # Pin passthrough to cores 0-1  
    if docker ps --format "table {{.Names}}" | grep -q "ballerina-passthrough"; then
        docker update --cpuset-cpus="$PASSTHROUGH_CORES" ballerina-passthrough
        log "✅ Passthrough pinned to CPU cores $PASSTHROUGH_CORES"
    fi
    
    # Wait a bit more for constraint application
    sleep 20
    
    # Verify services are responding
    verify_services
}

# Function to verify services are running
verify_services() {
    log "🔍 Verifying service health..."
    
    local passthrough_healthy=false
    local backend_healthy=false
    
    # Determine protocol based on SERVER_SSL
    local passthrough_protocol="http"
    if [ "$SERVER_SSL" = "true" ]; then
        passthrough_protocol="https"
    fi
    
    local backend_protocol="http"
    if [ "$BACKEND_SSL" = "true" ]; then
        backend_protocol="https"
    fi
    
    # Check passthrough service with dynamic port and protocol
    if curl -k -f "${passthrough_protocol}://localhost:${SERVER_PORT}/passthrough" --max-time 5 --data '{"test": "health"}' --header "Content-Type: application/json" >/dev/null 2>&1; then
        passthrough_healthy=true
    fi
    
    # Check backend service with dynamic port and protocol
    if curl -k -f "${backend_protocol}://localhost:${BACKEND_PORT}/service/EchoService" --max-time 5 --data '{"test": "health"}' --header "Content-Type: application/json" >/dev/null 2>&1; then
        backend_healthy=true
    fi
    
    if [ "$passthrough_healthy" = true ] && [ "$backend_healthy" = true ]; then
        log "✅ Services are healthy and responding"
    else
        log "⚠️  Services may be initializing, proceeding with reduced validation..."
        # Just check if containers are running instead of strict health check
        if docker ps --filter "name=ballerina-passthrough" --filter "status=running" | grep -q ballerina-passthrough && \
           docker ps --filter "name=netty-backend" --filter "status=running" | grep -q netty-backend; then
            log "✅ Both containers are running, proceeding with test"
        else
            error "❌ Service containers not running"
            docker compose -f "$DOCKER_COMPOSE_FILE" logs
            exit 1
        fi
    fi
}

# Function to run load test with statistical analysis
run_load_test_with_stats() {
    local service=$1
    local file_size=$2
    local users=$3
    local test_id="${service}_${file_size}_${users}users"
    
    log "📊 Running statistical load test: $test_id"
    log "Configuration: ${NUM_RUNS} runs, warmup: ${WARMUP_DURATION}s, test: ${TEST_DURATION}s"
    
    # Create test-specific results directory
    local test_results_dir="$RESULTS_DIR/$test_id"
    mkdir -p "$test_results_dir"
    
    # Array to store throughput results
    local throughput_results=()
    local latency_results=()
    
    # Run multiple iterations
    for run in $(seq 1 $NUM_RUNS); do
        log "🔄 Run $run/$NUM_RUNS for $test_id"
        
        local run_results_dir="$test_results_dir/run_$run"
        mkdir -p "$run_results_dir"
        
        # Start CPU monitoring
        local cpu_monitor_file="$run_results_dir/cpu_usage.csv"
        monitor_cpu_usage $((WARMUP_DURATION + TEST_DURATION + COOLDOWN_DURATION)) "$cpu_monitor_file" &
        local cpu_monitor_pid=$!
        
        # Run warmup phase
        log "🔥 Warmup phase: ${WARMUP_DURATION}s"
        run_h2load_test "$service" "$file_size" "$users" "$WARMUP_DURATION" "$run_results_dir/warmup" true
        
        log "⏱️  Cooldown: ${COOLDOWN_DURATION}s"
        sleep $COOLDOWN_DURATION
        
        # Run actual test
        log "🎯 Test phase: ${TEST_DURATION}s"
        run_h2load_test "$service" "$file_size" "$users" "$TEST_DURATION" "$run_results_dir/test" false
        
        # Stop CPU monitoring
        kill $cpu_monitor_pid 2>/dev/null || true
        
        # Parse results
        local throughput=$(parse_throughput "$run_results_dir/test_h2load.txt")
        local avg_latency=$(parse_avg_latency "$run_results_dir/test_h2load.txt")
        
        # Store results (skip first run if configured)
        if [ "$DISCARD_FIRST_RUN" = true ] && [ "$run" -eq 1 ]; then
            warn "🗑️  Discarding first run (warmup run)"
        else
            throughput_results+=("$throughput")
            latency_results+=("$avg_latency")
        fi
        
        log "Run $run results: ${throughput} req/s, ${avg_latency}ms latency"
        
        # Cooldown between runs
        if [ "$run" -lt "$NUM_RUNS" ]; then
            log "😴 Inter-run cooldown: ${COOLDOWN_DURATION}s"
            sleep $COOLDOWN_DURATION
        fi
    done
    
    # Calculate statistics
    calculate_and_report_statistics "$test_id" "${throughput_results[@]}" "${latency_results[@]}"
}

# Function to run h2load test
run_h2load_test() {
    local service=$1
    local file_size=$2
    local users=$3
    local duration=$4
    local output_prefix=$5
    local is_warmup=$6
    
    # Use the configured service parameters (from configure_services)
    local protocol="http"
    if [ "$SERVER_SSL" = "true" ]; then
        protocol="https"
    fi
    
    # Prepare test data  
    local data_file="/app/samples/${file_size}.txt"
    
    # Build test URL using container network hostname
    local test_url="${protocol}://ballerina-passthrough:${SERVER_PORT}/passthrough"
    
    # Determine HTTP version for h2load based on server configuration
    local h2load_version=""
    if [ "$SERVER_HTTP2" = "false" ]; then
        h2load_version="--h1"
    fi
    
    # Run h2load in container (CPU cores 4-7)
    local h2load_output="${output_prefix}_h2load.txt"
    
    log "Running h2load: $users users, ${duration}s duration"
    
    # Ensure h2load container is running and pinned
    if ! docker ps --format "table {{.Names}}" | grep -q "h2load-client"; then
        log "Starting h2load container..."
        docker compose -f "$DOCKER_COMPOSE_FILE" up -d h2load
        sleep 5
        
        # Pin h2load to cores 4-7
        docker update --cpuset-cpus="$H2LOAD_CORES" h2load-client
        log "✅ h2load pinned to CPU cores 4-7"
        sleep 5
    fi
    
    # Execute h2load in the dedicated container
    docker compose -f "$DOCKER_COMPOSE_FILE" exec -T h2load \
        h2load -c "$users" -t 4 -D "$duration" -d "$data_file" \
        $h2load_version "$test_url" > "$h2load_output" 2>&1
    
    if [ $? -ne 0 ]; then
        error "h2load test failed for $service"
        cat "$h2load_output"
        return 1
    fi
}

# Function to prepare test data
prepare_test_data() {
    local size=$1
    local output_file=$2
    
    case "$size" in
        "50B") dd if=/dev/zero bs=1 count=50 2>/dev/null | tr '\0' 'A' > "$output_file" ;;
        "1KB") dd if=/dev/zero bs=1024 count=1 2>/dev/null | tr '\0' 'A' > "$output_file" ;;
        "10KB") dd if=/dev/zero bs=1024 count=10 2>/dev/null | tr '\0' 'A' > "$output_file" ;;
        "100KB") dd if=/dev/zero bs=1024 count=100 2>/dev/null | tr '\0' 'A' > "$output_file" ;;
        "500KB") dd if=/dev/zero bs=1024 count=500 2>/dev/null | tr '\0' 'A' > "$output_file" ;;
        "1MB") dd if=/dev/zero bs=1024 count=1024 2>/dev/null | tr '\0' 'A' > "$output_file" ;;
        *) echo "A" > "$output_file" ;;
    esac
}

# Function to parse throughput from h2load output
parse_throughput() {
    local h2load_file=$1
    grep "finished in.*req/s" "$h2load_file" | sed -n 's/.*finished in [0-9.]*s, \([0-9.]*\) req\/s.*/\1/p' || echo "0"
}

# Function to parse average latency
parse_avg_latency() {
    local h2load_file=$1
    grep "time for request:" "$h2load_file" | awk '{print $6}' | sed 's/[^0-9.]//g' || echo "0"
}

# Function to calculate statistics
calculate_and_report_statistics() {
    local test_id=$1
    shift
    local throughput_values=("$@")
    
    # Split throughput and latency (assuming they're passed alternately)
    local throughput_array=()
    local latency_array=()
    local count=${#throughput_values[@]}
    
    for ((i=0; i<count/2; i++)); do
        throughput_array+=("${throughput_values[$i]}")
        latency_array+=("${throughput_values[$((i+count/2))]}")
    done
    
    # Calculate throughput statistics
    local throughput_sum=0
    local throughput_count=${#throughput_array[@]}
    
    if [ $throughput_count -gt 0 ]; then
        for val in "${throughput_array[@]}"; do
            throughput_sum=$(echo "$throughput_sum + $val" | bc -l)
        done
        
        local throughput_mean=$(echo "scale=2; $throughput_sum / $throughput_count" | bc -l)
        
        # Calculate standard deviation
        local throughput_variance_sum=0
        for val in "${throughput_array[@]}"; do
            local diff=$(echo "$val - $throughput_mean" | bc -l)
            local squared=$(echo "$diff * $diff" | bc -l)
            throughput_variance_sum=$(echo "$throughput_variance_sum + $squared" | bc -l)
        done
        
        local throughput_variance=$(echo "scale=4; $throughput_variance_sum / $throughput_count" | bc -l)
        local throughput_stddev=$(echo "scale=2; sqrt($throughput_variance)" | bc -l)
        local throughput_cv=$(echo "scale=4; $throughput_stddev / $throughput_mean * 100" | bc -l)
        
        # Report statistics
        log "📈 Statistical Analysis for $test_id:"
        log "   Throughput Mean: ${throughput_mean} req/s"
        log "   Throughput StdDev: ${throughput_stddev} req/s"  
        log "   Coefficient of Variation: ${throughput_cv}%"
        
        # Check if CV is within acceptable range
        if (( $(echo "$throughput_cv < 3.0" | bc -l) )); then
            log "✅ Excellent consistency (CV < 3%)"
        elif (( $(echo "$throughput_cv < 5.0" | bc -l) )); then
            warn "⚠️  Good consistency (CV < 5%)"
        else
            warn "⚠️  Poor consistency (CV >= 5%) - consider more runs or longer warmup"
        fi
        
        # Save detailed statistics
        local stats_file="$RESULTS_DIR/${test_id}_statistics.csv"
        {
            echo "metric,mean,stddev,cv_percent,min,max"
            echo "throughput_rps,$throughput_mean,$throughput_stddev,$throughput_cv,$(printf '%s\n' "${throughput_array[@]}" | sort -n | head -1),$(printf '%s\n' "${throughput_array[@]}" | sort -n | tail -1)"
        } > "$stats_file"
        
        log "📄 Detailed statistics saved to: $stats_file"
    fi
}

# Helper functions for service configuration
get_service_port() {
    local service=$1
    case "$service" in
        "h1-h1") echo "9091" ;;
        "h1c-h1") echo "9092" ;;
        "h1-h1c") echo "9093" ;;
        "h1c-h1c") echo "9094" ;;
        "h2-h2") echo "9095" ;;
        "h2c-h2") echo "9096" ;;
        "h2-h2c") echo "9097" ;;
        "h2c-h2c") echo "9098" ;;
        "h1-h2") echo "9099" ;;
        "h1c-h2") echo "9100" ;;
        "h1-h2c") echo "9101" ;;
        "h1c-h2c") echo "9102" ;;
        "h2-h1") echo "9103" ;;
        "h2c-h1") echo "9104" ;;
        "h2-h1c") echo "9105" ;;
        "h2c-h1c") echo "9106" ;;
        *) echo "9094" ;;
    esac
}

get_service_protocol() {
    local service=$1
    if [[ "$service" =~ ^h1-|^h1c-h1$|^h1-h1c$|^h1c-h1c$ ]]; then
        if [[ "$service" =~ c ]]; then
            echo "http"
        else
            echo "https"
        fi
    else
        if [[ "$service" =~ c ]]; then
            echo "http"
        else
            echo "https"
        fi
    fi
}

# Function to cleanup Docker environment
cleanup() {
    log "🧹 Cleaning up Docker environment..."
    
    docker compose -f "$DOCKER_COMPOSE_FILE" down -v
    
    # Optional: Remove images (uncomment if needed)
    # docker compose -f "$DOCKER_COMPOSE_FILE" down --rmi all -v
    
    log "✅ Cleanup completed"
}

# Function to cleanup containers only (keep images for next service)
cleanup_containers() {
    log "🧹 Stopping containers for service reconfiguration..."
    
    docker compose -f "$DOCKER_COMPOSE_FILE" stop
    docker compose -f "$DOCKER_COMPOSE_FILE" rm -f
    
    log "✅ Containers stopped"
}

# Function to display help
show_help() {
    cat << EOF
Dockerized Ballerina HTTP Load Testing with CPU Isolation

USAGE:
    ./docker_load_test.sh [COMMAND] [OPTIONS]

COMMANDS:
    build           Build Docker images
    test            Run load tests with CPU isolation (default)
    cleanup         Stop containers and cleanup
    help            Show this help message

OPTIONS:
    -s, --services SERVICES     Comma-separated service names (default: h1c-h1c,h2c-h2c,h1c-h2c)
    -f, --files SIZES          Comma-separated file sizes (default: 1KB,10KB,100KB) 
    -u, --users USERS          Comma-separated user counts (default: 100)
    -r, --runs RUNS            Number of statistical runs (default: 5)
    -w, --warmup SECONDS       Warmup duration in seconds (default: 300)
    -d, --duration SECONDS     Test duration in seconds (default: 900)
    --no-discard              Keep results from first run (default: discard)

DESCRIPTION:
    This script provides CPU-isolated load testing using Docker containers:
    • Passthrough Service: CPU cores 0-1
    • Backend Service: CPU cores 2-3  
    • h2load Client: CPU cores 4-7
    
    Statistical Analysis:
    • Runs multiple iterations for confidence
    • Calculates mean, standard deviation, coefficient of variation
    • Monitors CPU usage to prevent oversaturation
    • Target CV < 3% for excellent consistency

EXAMPLES:
    # Build images and run default tests
    ./docker_load_test.sh build
    ./docker_load_test.sh test
    
    # Custom test configuration
    ./docker_load_test.sh test -s "h1c-h1c,h2c-h2c" -f "1KB,10KB" -u "50,100" -r 3
    
    # Quick consistency test
    ./docker_load_test.sh test -s "h1c-h1c" -f "1KB" -u "50" -r 3 -w 120 -d 300

PREREQUISITES:
    • Docker and Docker Compose
    • Minimum 8 CPU cores (4 cores minimum)
    • Built Ballerina and Netty projects
EOF
}

# Parse command line arguments
COMMAND="test"
if [ $# -gt 0 ] && [[ ! "$1" =~ ^- ]]; then
    COMMAND=$1
    shift
fi

# Initialize arrays with defaults
SERVICES=("${DEFAULT_SERVICES[@]}")  
FILE_SIZES=("${DEFAULT_FILE_SIZES[@]}")
CONCURRENT_USERS=("${DEFAULT_CONCURRENT_USERS[@]}")

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--services)
            IFS=',' read -ra SERVICES <<< "$2"
            shift 2
            ;;
        -f|--files|--file-sizes)
            IFS=',' read -ra FILE_SIZES <<< "$2"
            shift 2
            ;;
        -u|--users)
            IFS=',' read -ra CONCURRENT_USERS <<< "$2"
            shift 2
            ;;
        -r|--runs)
            NUM_RUNS="$2"
            shift 2
            ;;
        -w|--warmup)
            WARMUP_DURATION="$2"
            shift 2
            ;;
        -d|--duration)
            TEST_DURATION="$2"
            shift 2
            ;;
        --no-discard)
            DISCARD_FIRST_RUN=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Execute command
case $COMMAND in
    build)
        check_cpu_cores
        build_docker_images
        ;;
    test)
        check_cpu_cores
        
        log "🚀 Starting Dockerized Load Testing with CPU Isolation"
        log "Services: ${SERVICES[*]}"
        log "File sizes: ${FILE_SIZES[*]}"
        log "Concurrent users: ${CONCURRENT_USERS[*]}"
        log "Statistical runs: $NUM_RUNS"
        log "Warmup: ${WARMUP_DURATION}s, Test: ${TEST_DURATION}s"
        
        # Run load tests for each service configuration
        for service in "${SERVICES[@]}"; do
            log "🔄 Configuring and starting services for: $service"
            
            # Configure and start services for this specific service type
            start_services "$service"
            
            # Run tests for this service configuration
            for file_size in "${FILE_SIZES[@]}"; do
                for users in "${CONCURRENT_USERS[@]}"; do
                    run_load_test_with_stats "$service" "$file_size" "$users"
                done
            done
            
            # Cleanup services before testing next service type
            if [ ${#SERVICES[@]} -gt 1 ]; then
                log "🧹 Cleaning up services before next configuration..."
                cleanup_containers
            fi
        done
        
        log "🎉 All tests completed! Results in: $RESULTS_DIR"
        ;;
    cleanup)
        cleanup
        ;;
    help)
        show_help
        ;;
    *)
        error "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac