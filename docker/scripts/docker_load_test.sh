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
    local available_cores=$(nproc)
    
    if [ "$available_cores" -lt "$required_cores" ]; then
        error "Insufficient CPU cores. Required: $required_cores, Available: $available_cores"
        warn "Adjusting CPU allocation to available cores..."
        
        # Adjust CPU allocation based on available cores
        if [ "$available_cores" -ge 6 ]; then
            warn "Using cores 0-1 for Passthrough, 2-3 for Backend, 4-$(($available_cores-1)) for h2load"
        elif [ "$available_cores" -ge 4 ]; then
            warn "Using cores 0 for Passthrough, 1 for Backend, 2-$(($available_cores-1)) for h2load"
        else
            error "Minimum 4 cores required for proper isolation"
            exit 1
        fi
    else
        log "✅ CPU allocation: Passthrough(0-1), Backend(2-3), h2load(4-7)"
    fi
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
            local cpu_stats=$(sar -u $CPU_MONITOR_INTERVAL 1 | tail -1)
            local cpu_idle=$(echo "$cpu_stats" | awk '{print $NF}')
            local cpu_total=$(echo "100 - $cpu_idle" | bc -l)
            
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
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    
    # Start backend service first
    log "Starting Netty backend (CPU cores 2-3)..."
    docker compose -f "$DOCKER_COMPOSE_FILE" up -d backend
    
    # Start passthrough service
    log "Starting Ballerina passthrough (CPU cores 0-1)..."  
    docker compose -f "$DOCKER_COMPOSE_FILE" up -d passthrough
    
    # Wait for services to start
    log "Waiting for services to initialize..."
    sleep 10
    
    # Apply CPU constraints manually using docker update
    log "Applying CPU core constraints..."
    
    # Pin backend to cores 2-3
    if docker ps --format "table {{.Names}}" | grep -q "netty-backend"; then
        docker update --cpuset-cpus="2,3" netty-backend
        log "✅ Backend pinned to CPU cores 2-3"
    fi
    
    # Pin passthrough to cores 0-1  
    if docker ps --format "table {{.Names}}" | grep -q "ballerina-passthrough"; then
        docker update --cpuset-cpus="0,1" ballerina-passthrough
        log "✅ Passthrough pinned to CPU cores 0-1"
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
    
    # Check a few representative endpoints
    for port in 9094 8701; do
        local protocol="http"
        if curl -k -f "${protocol}://localhost:${port}/passthrough" --max-time 5 >/dev/null 2>&1; then
            if [ "$port" = "9094" ]; then
                passthrough_healthy=true
            else
                backend_healthy=true
            fi
        fi
    done
    
    if [ "$passthrough_healthy" = true ] && [ "$backend_healthy" = true ]; then
        log "✅ Services are healthy and responding"
    else
        error "❌ Service health check failed"
        docker compose -f "$DOCKER_COMPOSE_FILE" logs
        exit 1
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
    
    # Get service configuration
    local port=$(get_service_port "$service")
    local protocol=$(get_service_protocol "$service")
    
    # Prepare test data
    local data_file="/tmp/test_data_${file_size}.txt"
    prepare_test_data "$file_size" "$data_file"
    
    # Build test URL
    local test_url="${protocol}://passthrough:${port}/passthrough"
    
    # Determine HTTP version for h2load
    local h2load_version=""
    if [[ "$service" =~ ^h1 ]]; then
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
        docker update --cpuset-cpus="4,5,6,7" h2load-client
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
        
        # Start services
        start_services
        
        # Run load tests
        for service in "${SERVICES[@]}"; do
            for file_size in "${FILE_SIZES[@]}"; do
                for users in "${CONCURRENT_USERS[@]}"; do
                    run_load_test_with_stats "$service" "$file_size" "$users"
                done
            done
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