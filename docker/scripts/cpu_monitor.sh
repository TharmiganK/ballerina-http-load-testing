#!/bin/bash

# CPU Core Monitoring and Validation Script
# Monitors CPU usage per core and validates resource isolation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to check CPU core allocation
check_cpu_allocation() {
    log "🔍 Checking CPU core allocation..."
    
    local total_cores=$(nproc)
    log "Total CPU cores available: $total_cores"
    
    if [ "$total_cores" -lt 8 ]; then
        warn "Recommended: 8+ cores for optimal isolation"
        warn "Available: $total_cores cores"
        
        if [ "$total_cores" -lt 4 ]; then
            error "Minimum 4 cores required"
            exit 1
        fi
    fi
    
    # Show recommended allocation
    log "📋 CPU Core Allocation (Applied via docker update):"
    echo "   Passthrough Service: cores 0-1 (2 cores) - Applied after container start"
    echo "   Backend Service: cores 2-3 (2 cores) - Applied after container start" 
    echo "   h2load Client: cores 4-7 (4 cores) - Applied before test execution"
    echo "   OS/System: remaining cores"
    echo ""
    echo "Note: CPU constraints are applied using 'docker update --cpuset-cpus' after"
    echo "      container startup to ensure compatibility with modern Docker Compose."
}

# Function to monitor Docker container CPU usage
monitor_docker_cpu() {
    local duration=${1:-60}
    local output_file="$PROJECT_ROOT/docker-results/cpu_monitoring.csv"
    
    log "📊 Monitoring Docker container CPU usage for ${duration}s..."
    
    mkdir -p "$(dirname "$output_file")"
    
    {
        echo "timestamp,container,cpu_percent,memory_usage,memory_limit"
        
        for ((i=0; i<=duration; i+=5)); do
            local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            
            # Get CPU and memory stats for our containers
            docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
                ballerina-passthrough netty-backend h2load-client 2>/dev/null | \
                tail -n +2 | while IFS=$'\t' read -r container cpu_percent mem_usage; do
                    echo "$timestamp,$container,$cpu_percent,$mem_usage"
                done
            
            sleep 5
        done
    } > "$output_file"
    
    log "💾 CPU monitoring data saved to: $output_file"
}

# Function to validate CPU isolation effectiveness
validate_cpu_isolation() {
    local results_file="$1"
    
    if [ ! -f "$results_file" ]; then
        error "CPU monitoring results file not found: $results_file"
        return 1
    fi
    
    log "📈 Analyzing CPU isolation effectiveness..."
    
    # Parse CPU usage for each container
    local passthrough_avg=$(grep "ballerina-passthrough" "$results_file" | \
        awk -F',' '{gsub(/%/, "", $3); sum+=$3; count++} END {if(count>0) print sum/count; else print 0}')
    
    local backend_avg=$(grep "netty-backend" "$results_file" | \
        awk -F',' '{gsub(/%/, "", $3); sum+=$3; count++} END {if(count>0) print sum/count; else print 0}')
    
    local h2load_avg=$(grep "h2load-client" "$results_file" | \
        awk -F',' '{gsub(/%/, "", $3); sum+=$3; count++} END {if(count>0) print sum/count; else print 0}')
    
    log "🎯 CPU Usage Analysis:"
    echo "   Passthrough Service: ${passthrough_avg}%"
    echo "   Backend Service: ${backend_avg}%"
    echo "   h2load Client: ${h2load_avg}%"
    
    # Validate isolation effectiveness
    local total_usage=$(echo "$passthrough_avg + $backend_avg + $h2load_avg" | bc -l)
    
    if (( $(echo "$total_usage < 90" | bc -l) )); then
        log "✅ Good CPU resource utilization (${total_usage}% total)"
    elif (( $(echo "$total_usage < 95" | bc -l) )); then
        warn "⚠️  High CPU utilization (${total_usage}% total) - still acceptable"
    else
        warn "⚠️  Very high CPU utilization (${total_usage}% total) - may affect results"
    fi
}

# Function to generate system resource report
generate_resource_report() {
    local output_file="$PROJECT_ROOT/docker-results/system_resource_report.md"
    
    log "📄 Generating system resource report..."
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$output_file")"
    
    {
        echo "# System Resource Report"
        echo "Generated: $(date)"
        echo ""
        
        echo "## System Information"
        echo "- OS: $(uname -s) $(uname -r)"
        echo "- Architecture: $(uname -m)"
        echo "- CPU Cores: $(nproc)"
        if command -v free &> /dev/null; then
            echo "- Memory: $(free -h | grep '^Mem:' | awk '{print $2}') total"
        else
            # macOS alternative
            echo "- Memory: $(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))GB total"
        fi
        echo ""
        
        echo "## Docker Information" 
        echo "- Docker Version: $(docker --version)"
        echo "- Docker Compose Version: $(docker compose version --short)"
        echo ""
        
        echo "## CPU Core Allocation Strategy"
        echo "| Component | CPU Cores | Docker Constraint |"
        echo "|-----------|-----------|-------------------|"
        echo "| Passthrough Service | 0-1 | \`--cpuset-cpus=\"0,1\"\` |"
        echo "| Backend Service | 2-3 | \`--cpuset-cpus=\"2,3\"\` |" 
        echo "| h2load Client | 4-7 | \`--cpuset-cpus=\"4,5,6,7\"\` |"
        echo ""
        
        echo "## Resource Constraints"
        echo "- Memory Limit: 2GB per container"
        echo "- CPU Limit: 2.0 cores (Passthrough/Backend), 4.0 cores (h2load)"
        echo "- CPU Reservation: 1.5 cores (Passthrough/Backend), 3.0 cores (h2load)"
        echo ""
        
        echo "## Test Configuration"
        echo "- Warmup Duration: 5 minutes"
        echo "- Test Duration: 15 minutes"
        echo "- Statistical Runs: 5 iterations"
        echo "- Target CV: < 3% for excellent consistency"
        
    } > "$output_file"
    
    log "📋 Resource report saved to: $output_file"
}

# Function to check Docker environment
check_docker_environment() {
    log "🐳 Checking Docker environment..."
    
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed"
        exit 1
    fi
    
    if ! command -v docker compose &> /dev/null; then
        error "Docker Compose is not installed"
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running"
        exit 1
    fi
    
    log "✅ Docker environment is ready"
    
    # Check available resources
    local docker_info=$(docker system info --format json 2>/dev/null)
    if [ $? -eq 0 ]; then
        log "Docker system resources available"
    fi
}

# Function to show CPU affinity of running containers
show_container_cpu_affinity() {
    log "🎯 Checking container CPU affinity..."
    
    for container in "ballerina-passthrough" "netty-backend" "h2load-client"; do
        if docker ps --format "table {{.Names}}" | grep -q "$container"; then
            local pid=$(docker inspect -f '{{.State.Pid}}' "$container" 2>/dev/null)
            if [ -n "$pid" ] && [ "$pid" != "0" ]; then
                local affinity=$(taskset -p "$pid" 2>/dev/null | awk '{print $NF}' || echo "unavailable")
                log "   $container (PID $pid): CPU affinity $affinity"
            fi
        else
            warn "   $container: not running"
        fi
    done
}

# Main execution
case "${1:-check}" in
    "check")
        check_cpu_allocation
        check_docker_environment
        generate_resource_report
        ;;
    "monitor")
        monitor_docker_cpu "${2:-60}"
        ;;
    "validate")
        validate_cpu_isolation "$2"
        ;;
    "affinity")
        show_container_cpu_affinity
        ;;
    "report")
        generate_resource_report
        ;;
    *)
        echo "Usage: $0 {check|monitor [duration]|validate [results_file]|affinity|report}"
        echo ""
        echo "Commands:"
        echo "  check     - Check system requirements and Docker environment"
        echo "  monitor   - Monitor container CPU usage (default: 60s)"
        echo "  validate  - Validate CPU isolation from monitoring results"
        echo "  affinity  - Show CPU affinity of running containers"
        echo "  report    - Generate system resource report"
        exit 1
        ;;
esac