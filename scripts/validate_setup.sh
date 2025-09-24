#!/bin/bash

# Environment validation script for Ballerina Passthrough Load Testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BALLERINA_PROJECT_DIR="${PROJECT_ROOT}/ballerina-passthrough"
NETTY_BACKEND_DIR="${PROJECT_ROOT}/netty-backend"
NETTY_JAR="${NETTY_BACKEND_DIR}/netty-http-echo-service.jar"
BALLERINA_JAR="${BALLERINA_PROJECT_DIR}/target/bin/ballerina_passthrough.jar"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[✓] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[!] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[✗] $1${NC}"
}

info() {
    echo -e "${BLUE}[i] $1${NC}"
}

echo "=== Ballerina Passthrough Load Testing - Environment Check ==="
echo ""

all_good=true

info "Checking prerequisites..."

# Check Ballerina
if command -v bal &> /dev/null; then
    BAL_VERSION=$(bal version 2>/dev/null | head -n1 || echo "Unknown")
    log "bal is installed ($BAL_VERSION)"
else
    error "bal is not installed"
    all_good=false
fi

# Check Java
if command -v java &> /dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | head -n1 || echo "Unknown")
    log "java is installed ($JAVA_VERSION)"
else
    error "java is not installed"
    all_good=false
fi

# Check JMeter
if command -v jmeter &> /dev/null; then
    JMETER_VERSION=$(jmeter --version 2>/dev/null | head -n1 || echo "Unknown")
    log "jmeter is installed ($JMETER_VERSION)"
else
    error "jmeter is not installed"
    echo "    Install with: brew install jmeter"
    all_good=false
fi

echo ""
info "Checking file structure..."

# Check directories
required_dirs=("ballerina-passthrough" "netty-backend" "resources" "samples")
for dir in "${required_dirs[@]}"; do
    if [ -d "$PROJECT_ROOT/$dir" ]; then
        log "Directory $dir exists"
    else
        error "Directory $dir is missing"
        all_good=false
    fi
done

# Check required files
required_files=("passthrough-test-simple.jmx" "scripts/run_load_tests.sh" "scripts/quick_test.sh" "scripts/clean_results.sh")
for file in "${required_files[@]}"; do
    if [ -f "$PROJECT_ROOT/$file" ]; then
        log "File $file exists"
    else
        error "File $file is missing"
        all_good=false
    fi
done

echo ""
info "Checking sample files..."

sample_files=("1KB.txt" "10KB.txt" "100KB.txt" "500KB.txt" "1MB.txt")
missing_samples=()

for file in "${sample_files[@]}"; do
    if [ -f "$PROJECT_ROOT/samples/$file" ]; then
        log "Sample file $file exists"
    else
        error "Sample file $file is missing"
        missing_samples+=("$file")
        all_good=false
    fi
done

if [ ${#missing_samples[@]} -gt 0 ]; then
    info "You can generate missing sample files with: ./generate_samples.sh"
fi

echo ""
info "Checking certificates..."

cert_files=("ballerinaKeystore.p12" "ballerinaTruststore.p12")
for file in "${cert_files[@]}"; do
    if [ -f "$PROJECT_ROOT/resources/$file" ]; then
        log "Certificate $file exists"
    else
        error "Certificate $file is missing"
        all_good=false
    fi
done

echo ""
info "Checking JAR files..."

# Check if Ballerina project exists
if [ -f "$PROJECT_ROOT/ballerina-passthrough/Ballerina.toml" ]; then
    log "Ballerina project configuration exists"
    
    # Check if JAR is built
    if [ -f "$BALLERINA_JAR" ]; then
        log "Ballerina JAR exists: ballerina_passthrough.jar"
        
        # Test JAR file integrity
        if file "$BALLERINA_JAR" | grep -q -E "(Java archive|Zip archive)"; then
            log "Ballerina JAR is valid"
        else
            error "Ballerina JAR appears to be corrupted"
            all_good=false
        fi
    else
        error "Ballerina JAR not found: $BALLERINA_JAR"
        info "Build it with: cd ballerina-passthrough && bal build"
        all_good=false
    fi
else
    error "Ballerina project configuration (Ballerina.toml) not found"
    all_good=false
fi

# Check netty JAR
if [ -f "$NETTY_JAR" ]; then
    log "Netty JAR exists: netty-http-echo-service.jar"
    
    # Test JAR file integrity
    if file "$NETTY_JAR" | grep -q -E "(Java archive|Zip archive)"; then
        log "Netty JAR is valid"
    else
        error "Netty JAR appears to be corrupted"
        all_good=false
    fi
else
    error "Netty JAR not found: $NETTY_JAR"
    all_good=false
fi

echo ""
info "Testing connectivity and ports..."

# Check if common ports are free
test_ports=(8688 8689 9091 9092 9093 9094)
for port in "${test_ports[@]}"; do
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        warn "Port $port is already in use"
    else
        log "Port $port is available"
    fi
done

echo ""
info "Checking script permissions..."

# Check script executability
scripts=("run_load_tests.sh" "quick_test.sh" "clean_results.sh")
for script in "${scripts[@]}"; do
    if [ -x "$PROJECT_ROOT/scripts/$script" ]; then
        log "Script $script is executable"
    else
        warn "Script $script is not executable"
        info "Fix with: chmod +x $script"
    fi
done

echo ""

if [ "$all_good" = true ]; then
    log "All prerequisites are met!"
    echo ""
    log "You can now run load tests with:"
    info "  ./run_load_tests.sh              # Full test suite"
    info "  ./quick_test.sh h1c-h1c 1KB 100  # Quick individual test"
    info "  ./run_load_tests.sh build        # Build project only"
    info "  ./run_load_tests.sh clean        # Clean test data"
else
    echo ""
    error "Some prerequisites are missing. Please fix the issues above."
    echo ""
    info "Common fixes:"
    info "  - Install missing tools: brew install ballerina jmeter"
    info "  - Build project: cd ballerina-passthrough && bal build" 
    info "  - Generate samples: ./generate_samples.sh"
    info "  - Make scripts executable: chmod +x *.sh"
    exit 1
fi