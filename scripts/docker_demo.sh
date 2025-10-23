#!/bin/bash

# Docker Load Testing Demo Script
# Demonstrates the new CPU-isolated load testing capabilities

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
info() { echo -e "${BLUE}[DEMO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to display section header
section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info "$1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to wait for user input
wait_for_user() {
    echo ""
    read -p "Press Enter to continue..." -n1 -s
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    section "1. Prerequisites Check"
    
    log "Checking system requirements..."
    
    # Check Docker
    if command -v docker &> /dev/null; then
        log "✅ Docker is installed: $(docker --version | head -1)"
    else
        error "❌ Docker is not installed"
        echo "Please install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check Docker Compose
    if command -v docker compose &> /dev/null; then
        log "✅ Docker Compose is installed: $(docker compose version --short)"
    else
        error "❌ Docker Compose is not installed"
        exit 1
    fi
    
    # Check CPU cores (matching docker_load_test.sh logic)
    local system_cores=$(nproc)
    local docker_cores=$(docker system info --format '{{.NCPU}}' 2>/dev/null || echo "$system_cores")
    local available_cores=$docker_cores
    
    log "CPU cores available: $available_cores (system: $system_cores)"
    
    # Determine CPU allocation based on available cores (same logic as docker_load_test.sh)
    if [ "$available_cores" -ge 8 ]; then
        log "✅ Optimal CPU configuration (8+ cores)"
        PASSTHROUGH_CORES="0,1"
        BACKEND_CORES="2,3"
        H2LOAD_CORES="4,5,6,7"
    elif [ "$available_cores" -ge 6 ]; then
        warn "⚠️  Good CPU configuration (6+ cores)"
        PASSTHROUGH_CORES="0,1"
        BACKEND_CORES="2,3"
        H2LOAD_CORES="4,5"
    elif [ "$available_cores" -ge 4 ]; then
        warn "⚠️  Minimum CPU configuration (4+ cores) - performance may be limited"
        PASSTHROUGH_CORES="0"
        BACKEND_CORES="1"
        H2LOAD_CORES="2,3"
    else
        error "❌ Insufficient CPU cores (minimum 4 required)"
        exit 1
    fi
    
    # Check if projects are built
    if [ -f "$PROJECT_ROOT/ballerina-passthrough/target/bin/ballerina_passthrough.jar" ] && \
       [ -f "$PROJECT_ROOT/netty-backend/target/netty-http-echo-service.jar" ]; then
        log "✅ Required JAR files are available"
    else
        warn "⚠️  Projects may need to be built first"
        info "The build process will handle this automatically"
    fi
    
    wait_for_user
}

# Function to demonstrate system resource analysis
demonstrate_resource_analysis() {
    section "2. System Resource Analysis"
    
    log "Running comprehensive system check..."
    "$PROJECT_ROOT/scripts/cpu_monitor.sh" check
    
    info "This analysis determines optimal CPU allocation based on available cores:"
    echo "  • Passthrough Service: CPU cores $PASSTHROUGH_CORES"
    echo "  • Backend Service: CPU cores $BACKEND_CORES"  
    echo "  • h2load Client: CPU cores $H2LOAD_CORES"
    echo "  • OS/System: Remaining cores for system processes"
    
    wait_for_user
}

# Function to build Docker images
build_docker_images() {
    section "3. Building Docker Images with Resource Constraints"
    
    log "Building projects and Docker images..."
    info "This step creates containerized versions of all components:"
    echo "  • Ballerina Passthrough Service (isolated to cores $PASSTHROUGH_CORES)"
    echo "  • Netty Backend Service (isolated to cores $BACKEND_CORES)"
    echo "  • h2load Load Generator (isolated to cores $H2LOAD_CORES)"
    
    "$PROJECT_ROOT/scripts/docker_load_test.sh" build
    
    log "✅ Docker images built successfully"
    wait_for_user
}

# Function to demonstrate quick consistency test
quick_consistency_test() {
    section "4. Quick Consistency Test"
    
    info "Running a quick test to demonstrate statistical consistency..."
    echo "Configuration:"
    echo "  • Service: h1c-h1c (HTTP/1.1 client → HTTP/1.1 server)"
    echo "  • Payload: 1KB"
    echo "  • Users: 50 concurrent"
    echo "  • Runs: 3 statistical iterations"
    echo "  • Warmup: 2 minutes (reduced for demo)"
    echo "  • Test: 5 minutes (reduced for demo)"
    
    log "Starting containerized test with CPU isolation..."
    
    "$PROJECT_ROOT/scripts/docker_load_test.sh" test \
        -s "h1c-h1c" -f "1KB" -u "50" -r 3 -w 120 -d 300
    
    log "✅ Quick test completed"
    
    info "Analyzing statistical consistency..."
    "$PROJECT_ROOT/scripts/statistical_analysis.sh" analyze "h1c-h1c_1KB_50users"
    
    wait_for_user
}

# Function to demonstrate CPU monitoring
demonstrate_cpu_monitoring() {
    section "5. CPU Monitoring Demonstration"
    
    info "Starting a background load test to demonstrate CPU monitoring..."
    
    # Start a background test
    log "Starting background test for monitoring demonstration..."
    timeout 180 "$PROJECT_ROOT/scripts/docker_load_test.sh" test \
        -s "h2c-h2c" -f "1KB" -u "25" -r 1 -w 60 -d 60 &
    local test_pid=$!
    
    sleep 30  # Let test start
    
    log "Monitoring CPU usage for 60 seconds..."
    "$PROJECT_ROOT/scripts/cpu_monitor.sh" monitor 60 &
    local monitor_pid=$!
    
    # Show container CPU affinity
    sleep 10
    log "Checking container CPU affinity..."
    "$PROJECT_ROOT/scripts/cpu_monitor.sh" affinity
    
    # Wait for monitoring to complete
    wait $monitor_pid 2>/dev/null || true
    wait $test_pid 2>/dev/null || true
    
    log "✅ CPU monitoring demonstration completed"
    
    if [ -f "$PROJECT_ROOT/docker-results/cpu_monitoring.csv" ]; then
        info "CPU monitoring data saved - you can analyze it later with:"
        echo "  ./scripts/cpu_monitor.sh validate docker-results/cpu_monitoring.csv"
    fi
    
    wait_for_user
}

# Function to demonstrate full protocol comparison
full_protocol_comparison() {
    section "6. Full Protocol Comparison Test"
    
    info "Running comprehensive protocol comparison..."
    echo "This demonstrates the main objective: comparing HTTP protocols with statistical confidence"
    echo ""
    echo "Test matrix:"
    echo "  • h1c-h1c: HTTP/1.1 client → HTTP/1.1 server (baseline)"
    echo "  • h2c-h2c: HTTP/2 client → HTTP/2 server (pure HTTP/2)"  
    echo "  • h1c-h2c: HTTP/1.1 client → HTTP/2 server (mixed scenario)"
    echo ""
    echo "Payload sizes: 1KB, 10KB"
    echo "Concurrent users: 100"
    echo "Statistical runs: 5 iterations each"
    echo "Warmup: 5 minutes per test"
    echo "Test duration: 15 minutes per test"
    echo ""
    
    warn "⚠️  This is a comprehensive test that will take approximately 3 hours"
    echo "Would you like to:"
    echo "  1) Run the full test (recommended for actual benchmarking)"
    echo "  2) Run a shortened version (5-minute tests for demonstration)"
    echo "  3) Skip this test"
    echo ""
    
    read -p "Choose option (1/2/3): " choice
    
    case $choice in
        1)
            log "Running full protocol comparison test..."
            "$PROJECT_ROOT/scripts/docker_load_test.sh" test \
                -s "h1c-h1c,h2c-h2c,h1c-h2c" -f "1KB,10KB" -u "100"
            ;;
        2)
            log "Running shortened protocol comparison test..."
            "$PROJECT_ROOT/scripts/docker_load_test.sh" test \
                -s "h1c-h1c,h2c-h2c,h1c-h2c" -f "1KB" -u "50" -r 3 -w 120 -d 300
            ;;
        3)
            info "Skipping full test - moving to results analysis..."
            return
            ;;
        *)
            warn "Invalid choice, skipping test..."
            return
            ;;
    esac
    
    log "✅ Protocol comparison completed"
    wait_for_user
}

# Function to demonstrate statistical analysis
demonstrate_statistical_analysis() {
    section "7. Statistical Analysis and Reporting"
    
    info "Analyzing all completed test results..."
    
    # Check if we have any results
    if [ -d "$PROJECT_ROOT/docker-results" ] && [ "$(ls -A $PROJECT_ROOT/docker-results)" ]; then
        log "Running comprehensive statistical analysis..."
        
        "$PROJECT_ROOT/scripts/statistical_analysis.sh" all
        
        info "Generated reports:"
        echo "  📊 Comprehensive Analysis: docker-results/load_test_analysis_report.md"
        echo "  📈 Configuration Comparison: docker-results/configuration_comparison.csv"
        echo "  🖥️  System Resource Report: docker-results/system_resource_report.md"
        
        # Show a sample of results if available
        local sample_dir=$(find "$PROJECT_ROOT/docker-results" -name "*_*KB_*users" -type d | head -1)
        if [ -n "$sample_dir" ] && [ -f "$sample_dir/$(basename $sample_dir)_summary.csv" ]; then
            local test_name=$(basename "$sample_dir")
            info "Sample results for $test_name:"
            echo ""
            
            local summary_file="$sample_dir/${test_name}_summary.csv"
            if [ -f "$summary_file" ]; then
                echo "Metric | Mean | Std Dev | CV% | Assessment"
                echo "-------|------|---------|-----|----------"
                
                local tp_line=$(grep "^throughput_rps," "$summary_file")
                if [ -n "$tp_line" ]; then
                    IFS=',' read -r _ tp_mean tp_stddev tp_cv _ _ _ <<< "$tp_line"
                    local assessment="Good"
                    if (( $(echo "$tp_cv < 3.0" | bc -l 2>/dev/null || echo 0) )); then
                        assessment="Excellent"
                    elif (( $(echo "$tp_cv >= 5.0" | bc -l 2>/dev/null || echo 0) )); then
                        assessment="Needs Improvement"
                    fi
                    echo "Throughput | $(printf "%.1f" $tp_mean) | $(printf "%.1f" $tp_stddev) | $(printf "%.1f" $tp_cv) | $assessment"
                fi
            fi
        fi
    else
        warn "No test results found - run some tests first!"
        info "You can run tests with: ./scripts/docker_load_test.sh test"
    fi
    
    wait_for_user
}

# Function to show next steps
show_next_steps() {
    section "8. Next Steps and Best Practices"
    
    info "🎯 Key Benefits of This Setup:"
    echo "  ✅ CPU isolation eliminates resource contention"
    echo "  ✅ Statistical analysis ensures reliable results"
    echo "  ✅ Coefficient of Variation (CV) < 3% indicates excellent consistency"
    echo "  ✅ Automated warmup prevents JVM/service initialization skew"
    echo "  ✅ Multiple runs provide statistical confidence"
    echo ""
    
    info "📋 Best Practices for Production Testing:"
    echo "  1. Always run full warmup periods (5+ minutes)"
    echo "  2. Use 5+ statistical runs for confidence"
    echo "  3. Monitor CPU usage to ensure < 90% utilization"
    echo "  4. Discard first run results (warmup outliers)"
    echo "  5. Target CV < 3% for excellent consistency"
    echo "  6. Document system configuration for repeatability"
    echo ""
    
    info "🔧 Customizing for Your Environment:"
    echo "  • Adjust CPU core allocation in docker-compose.yml"
    echo "  • Modify concurrent users based on your hardware"
    echo "  • Increase test duration for more stable results"
    echo "  • Add custom service configurations as needed"
    echo ""
    
    info "📊 Understanding Results:"
    echo "  • Throughput Mean: Average requests per second"
    echo "  • Standard Deviation: Measure of variability"
    echo "  • CV (Coefficient of Variation): Consistency indicator"
    echo "  • CV < 3%: Excellent repeatability"
    echo "  • CV 3-5%: Good consistency"  
    echo "  • CV > 5%: Needs improvement (more warmup/runs)"
    echo ""
    
    info "🚀 Ready-to-Use Commands:"
    echo ""
    echo "# Quick consistency test"
    echo "./scripts/docker_load_test.sh test -s \"h1c-h1c\" -f \"1KB\" -u \"50\" -r 3"
    echo ""
    echo "# Full protocol comparison"  
    echo "./scripts/docker_load_test.sh test -s \"h1c-h1c,h2c-h2c,h1c-h2c\" -f \"1KB,10KB\" -u \"100\""
    echo ""
    echo "# Monitor CPU during tests"
    echo "./scripts/cpu_monitor.sh monitor 300"
    echo ""
    echo "# Analyze results"
    echo "./scripts/statistical_analysis.sh all"
    echo ""
    echo "# Cleanup when done"
    echo "./scripts/docker_load_test.sh cleanup"
    echo ""
}

# Function to cleanup
cleanup_demo() {
    section "9. Cleanup"
    
    log "Cleaning up Docker containers and resources..."
    "$PROJECT_ROOT/scripts/docker_load_test.sh" cleanup || true
    
    log "✅ Demo cleanup completed"
    
    info "Demo files and results are preserved in:"
    echo "  📁 docker-results/ - Test results and analysis"
    echo "  📁 docker/ - Docker configuration and documentation"
    echo "  📄 docker/README.md - Comprehensive setup guide"
}

# Main execution
main() {
    clear
    
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                    Docker-Based Load Testing Demo                            ║"
    echo "║                     CPU Isolation & Statistical Analysis                     ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    info "This demo showcases the enhanced load testing framework with:"
    echo "  🐳 Docker containerization for component isolation"
    echo "  🧮 CPU core allocation to prevent resource contention"
    echo "  📊 Statistical analysis with multiple runs"
    echo "  📈 Coefficient of Variation (CV) consistency metrics"
    echo "  ⏱️  Extended warmup and test durations"
    echo ""
    
    read -p "Ready to start? (y/N): " -n1 response
    echo ""
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log "Demo cancelled. Run './scripts/docker_demo.sh' when ready."
        exit 0
    fi
    
    # Execute demo steps
    check_prerequisites
    demonstrate_resource_analysis  
    build_docker_images
    quick_consistency_test
    demonstrate_cpu_monitoring
    full_protocol_comparison
    demonstrate_statistical_analysis
    show_next_steps
    cleanup_demo
    
    section "🎉 Demo Complete!"
    
    info "Your load testing environment is now ready for production use!"
    echo ""
    echo "Key takeaways:"
    echo "  ✅ CPU isolation ensures consistent results"
    echo "  ✅ Statistical analysis provides confidence in measurements"
    echo "  ✅ Automated setup handles complexity"
    echo "  ✅ Comprehensive reporting shows performance insights"
    echo ""
    
    log "Thank you for exploring the Docker-based load testing framework!"
}

# Execute main function
main "$@"