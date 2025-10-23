#!/bin/bash

# Demo script showing complete workflow of the Ballerina HTTP Load Testing Framework
# This script demonstrates all key features and provides a quick overview

set -e

echo "=== Ballerina HTTP Load Testing Framework Demo ==="
echo

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "scripts/run_load_tests.sh" ]; then
    echo "Error: Please run this script from the project root directory"
    exit 1
fi

step "1. Validating environment setup"
./scripts/validate_setup.sh

echo
step "2. Building Ballerina project with clean build"
cd ballerina-passthrough
echo "Cleaning previous build..."
bal clean
if [ -f "Dependencies.toml" ]; then
    echo "Removing Dependencies.toml..."
    rm -f Dependencies.toml
fi
echo "Building project..."
bal build
cd ..

echo
step "3. Running a quick individual test (h1c-h1c with 5KB payload)"
info "This will test HTTP client -> HTTP server configuration"
info "Running 50 users for 10 seconds to demonstrate functionality"

./scripts/quick_test.sh h1c-h1c 5KB.txt 50 10s

echo
step "4. Demonstrating cleanup functionality"
info "Cleaning up test results..."
./scripts/clean_results.sh all

echo
step "5. Framework Overview"
info "Available test configurations:"
echo "  - h1-h1   (HTTPS client -> HTTPS server, port 9091)"
echo "  - h1c-h1  (HTTP client -> HTTPS server, port 9092)" 
echo "  - h1-h1c  (HTTPS client -> HTTP server, port 9093)"
echo "  - h1c-h1c (HTTP client -> HTTP server, port 9094)"

echo
info "Available payload sizes: 1KB.txt, 5KB.txt, 10KB.txt, 100KB.txt, 500KB.txt, 1MB.txt"

echo
info "To run full load tests on all configurations:"
echo "  ./scripts/run_load_tests.sh -u 100 -d 30s -f 10KB.txt"

echo
info "To run individual service tests:"
echo "  ./scripts/quick_test.sh h1-h1 10KB.txt 200 60s"

echo
step "6. Results and Reports"
info "After running tests, check:"
echo "  - results/ directory for raw h2load output (.csv files)"
echo "  - reports/ directory for HTML reports with detailed metrics"

echo
step "Demo completed successfully!"
info "The framework is ready for comprehensive load testing."
warn "For production testing, consider increasing user load and test duration."

echo
info "Example production test command:"
echo "  ./scripts/run_load_tests.sh -u 500 -d 300s -f 10KB.txt -c"