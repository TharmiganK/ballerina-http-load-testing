#!/bin/bash

# HTTP/2 Load Testing Demo Script
# This script demonstrates the new HTTP/2 testing capabilities

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Function to display help
show_help() {
    cat << EOF
Ballerina HTTP/2 Load Testing - Interactive Demo

USAGE:
    ./http2_demo.sh [OPTIONS]

OPTIONS:
    -h, --help      Show this help message and exit

DESCRIPTION:
    This interactive demo showcases HTTP/1.1 vs HTTP/2 performance comparisons
    by running selected test scenarios and showing results in real-time.
    
    The demo will guide you through:
    • HTTP/1.1 baseline testing (h1c-h1c)
    • Pure HTTP/2 testing (h2c-h2c) 
    • Mixed protocol scenarios (h1c-h2c)
    • SSL/TLS performance comparisons (h1-h1 vs h2-h2)
    
    Each test uses small payloads (1KB) with 10 concurrent users for 5 seconds
    to provide quick feedback while demonstrating protocol differences.

TEST SCENARIOS:
    1. h1c-h1c  - HTTP/1.1 baseline (no SSL)
    2. h2c-h2c  - HTTP/2 equivalent (no SSL)  
    3. h1c-h2c  - Mixed HTTP/1.1 client → HTTP/2 backend
    4. h1-h1    - HTTP/1.1 with SSL
    5. h2-h2    - HTTP/2 with SSL

OUTPUT:
    • Terminal output showing configuration and progress
    • CSV results displayed after each test
    • Quick results saved in quick_results/ directory

PREREQUISITES:
    • Built Ballerina and Netty projects (run './run_load_tests.sh build' first)
    • h2load tool installed
    • Available ports 9091-9106 and 8688-8693

EXAMPLES:
    # Start interactive demo
    ./http2_demo.sh
    
    # Show help
    ./http2_demo.sh --help

SEE ALSO:
    • ./quick_test.sh        - Manual individual service testing
    • ./run_load_tests.sh    - Comprehensive load testing suite
    • HTTP2_EXTENSION.md     - Complete HTTP/2 documentation

EOF
}

# Check for help flags
if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
    show_help
    exit 0
fi

echo "=== Ballerina HTTP/2 Load Testing Demo ==="
echo "This demo showcases HTTP/1.1 vs HTTP/2 performance comparisons"
echo

# Function to run a quick test and show results
run_demo_test() {
    local service=$1
    local description=$2
    
    echo "--- Testing: $service ---"
    echo "Description: $description"
    echo "Command: ./scripts/quick_test.sh $service 1KB 10 5"
    echo
    
    # Run the test with timeout to prevent hanging
    if timeout 60 ./scripts/quick_test.sh "$service" 1KB 10 5; then
        echo "✅ Test completed successfully"
        
        # Show the results if CSV was generated
        result_file="quick_results/quick_test_${service}_1KB_10users.csv"
        if [ -f "$result_file" ]; then
            echo "📊 Results:"
            cat "$result_file"
        fi
    else
        echo "⚠️ Test timed out or failed"
    fi
    echo
    echo "Press Enter to continue..."
    read -r
}

cd "$PROJECT_ROOT"

echo "Building projects..."
./scripts/run_load_tests.sh build
echo "✅ Build completed"
echo

# Demo 1: HTTP/1.1 baseline
run_demo_test "h1c-h1c" "HTTP/1.1 client → HTTP/1.1 backend (baseline, no SSL)"

# Demo 2: Pure HTTP/2
run_demo_test "h2c-h2c" "HTTP/2 client → HTTP/2 backend (pure HTTP/2, no SSL)"

# Demo 3: Mixed scenario 
run_demo_test "h1c-h2c" "HTTP/1.1 client → HTTP/2 backend (mixed scenario, no SSL)"

# Demo 4: SSL comparison
echo "--- SSL Performance Comparison ---"
echo "Testing HTTP/1.1 vs HTTP/2 with SSL/TLS..."
echo

run_demo_test "h1-h1" "HTTP/1.1 client → HTTP/1.1 backend (with SSL)"
run_demo_test "h2-h2" "HTTP/2 client → HTTP/2 backend (with SSL)"

echo "=== Demo Complete ==="
echo
echo "Full service matrix (16 configurations available):"
echo "  Pure HTTP/1.1: h1-h1, h1c-h1, h1-h1c, h1c-h1c"
echo "  Pure HTTP/2:   h2-h2, h2c-h2, h2-h2c, h2c-h2c" 
echo "  Mixed H1→H2:   h1-h2, h1c-h2, h1-h2c, h1c-h2c"
echo "  Mixed H2→H1:   h2-h1, h2c-h1, h2-h1c, h2c-h1c"
echo
echo "Run full load tests with: ./scripts/run_load_tests.sh"
echo "View available services: ./scripts/quick_test.sh invalid_service"