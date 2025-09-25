#!/bin/bash

# Clean results and reports script
# Usage: ./clean_results.sh [results|reports|all]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="${PROJECT_ROOT}/results"
REPORTS_DIR="${PROJECT_ROOT}/reports"

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

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

clean_results() {
    if [ -d "$RESULTS_DIR" ] && [ "$(ls -A $RESULTS_DIR 2>/dev/null)" ]; then
        warn "Cleaning results directory..."
        rm -rf "${RESULTS_DIR}"/*
        log "Results directory cleaned"
    else
        info "Results directory is already clean"
    fi
}

clean_reports() {
    if [ -d "$REPORTS_DIR" ] && [ "$(ls -A $REPORTS_DIR 2>/dev/null)" ]; then
        warn "Cleaning reports directory..."
        rm -rf "${REPORTS_DIR}"/*
        log "Reports directory cleaned"
    else
        info "Reports directory is already clean"
    fi
}

show_usage() {
    echo "Usage: $0 [results|reports|all]"
    echo ""
    echo "Options:"
    echo "  results  - Clean only test results (*.csv files and logs)"
    echo "  reports  - Clean only HTML reports"
    echo "  all      - Clean both results and reports (default)"
    echo ""
    echo "Examples:"
    echo "  $0           # Clean everything"
    echo "  $0 all       # Clean everything"
    echo "  $0 results   # Clean only results"
    echo "  $0 reports   # Clean only reports"
}

# Parse command line argument
TARGET=${1:-"all"}

case $TARGET in
    "results")
        log "Cleaning test results..."
        clean_results
        ;;
    "reports")
        log "Cleaning HTML reports..."
        clean_reports
        ;;
    "all")
        log "Cleaning all test data..."
        clean_results
        clean_reports
        ;;
    "help"|"-h"|"--help")
        show_usage
        exit 0
        ;;
    *)
        echo "Error: Unknown option '$TARGET'"
        echo ""
        show_usage
        exit 1
        ;;
esac

log "Cleanup completed successfully"