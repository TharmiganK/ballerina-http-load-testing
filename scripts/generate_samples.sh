#!/bin/bash

# Sample file generator with random content for load testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SAMPLES_DIR="${PROJECT_ROOT}/samples"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[✓] $1${NC}"
}

info() {
    echo -e "${BLUE}[i] $1${NC}"
}

# Function to generate a file with random alphanumeric content
generate_random_file() {
    local filename=$1
    local size_bytes=$2
    local filepath="${SAMPLES_DIR}/${filename}"
    
    info "Generating ${filename} with ${size_bytes} bytes of random content..."
    
    # Create random alphanumeric content
    # Using a mix of letters, numbers, and some common characters for more realistic payload
    cat /dev/urandom | LC_CTYPE=C tr -dc 'a-zA-Z0-9.,!?;:()[]{}@#$%^&*_+-=<>/|\n ' | head -c "$size_bytes" > "$filepath"
    
    # Add a final newline to make it a proper text file
    echo >> "$filepath"
    
    log "Created ${filename} ($(ls -lh "$filepath" | awk '{print $5}'))"
}

# Function to generate JSON-like content for more realistic API testing
generate_json_like_file() {
    local filename=$1
    local target_size=$2
    local filepath="${SAMPLES_DIR}/${filename}"
    
    info "Generating ${filename} with JSON-like structure..."
    
    # Start with a basic JSON structure
    echo '{' > "$filepath"
    echo '  "metadata": {' >> "$filepath"
    echo '    "timestamp": "2025-09-24T14:39:00Z",' >> "$filepath"
    echo '    "version": "1.0",' >> "$filepath"
    echo '    "type": "load_test_payload"' >> "$filepath"
    echo '  },' >> "$filepath"
    echo '  "data": {' >> "$filepath"
    echo '    "payload": "' >> "$filepath"
    
    # Calculate how much random data we need
    local current_size=$(wc -c < "$filepath")
    local remaining_size=$((target_size - current_size - 100)) # Leave room for closing JSON
    
    if [ $remaining_size -gt 0 ]; then
        # Add random alphanumeric content
        cat /dev/urandom | LC_CTYPE=C tr -dc 'a-zA-Z0-9' | head -c "$remaining_size" >> "$filepath"
    fi
    
    echo '"' >> "$filepath"
    echo '  },' >> "$filepath"
    echo '  "test_info": {' >> "$filepath"
    echo '    "file_size": "'"${filename}"'",' >> "$filepath"
    echo '    "generated_by": "load_testing_framework"' >> "$filepath"
    echo '  }' >> "$filepath"
    echo '}' >> "$filepath"
    
    log "Created ${filename} ($(ls -lh "$filepath" | awk '{print $5}'))"
}

# Main function
main() {
    info "=== Sample File Generator ==="
    echo
    
    # Create samples directory if it doesn't exist
    mkdir -p "$SAMPLES_DIR"
    
    # File sizes in bytes - using regular arrays
    FILE_NAMES=("1KB" "5KB" "10KB" "100KB" "500KB" "1MB")
    FILE_SIZES=(1024 5120 10240 102400 512000 1048576)
    
    # Generate files
    for i in "${!FILE_NAMES[@]}"; do
        local size_name="${FILE_NAMES[$i]}"
        local size_bytes="${FILE_SIZES[$i]}"
        local filename="${size_name}.txt"
        
        # For smaller files, use JSON-like structure for more realistic testing
        if [ $size_bytes -le 10240 ]; then  # Files <= 10KB
            generate_json_like_file "$filename" "$size_bytes"
        else
            # For larger files, use pure random content for performance testing
            generate_random_file "$filename" "$size_bytes"
        fi
    done
    
    echo
    log "Sample file generation completed!"
    info "Generated files:"
    ls -lh "$SAMPLES_DIR"/*.txt | while read line; do
        filename=$(echo "$line" | awk '{print $9}' | xargs basename)
        size=$(echo "$line" | awk '{print $5}')
        echo "  - $filename: $size"
    done
    
    echo
    info "Files are ready for load testing!"
    
    # Show sample content for verification
    echo
    info "Sample content preview (first 200 chars of 1KB.txt):"
    head -c 200 "${SAMPLES_DIR}/1KB.txt" | cat -v
    echo
    echo "..."
}

# Handle command line arguments
case "${1:-}" in
    "clean")
        info "Cleaning existing sample files..."
        rm -f "${SAMPLES_DIR}"/*.txt
        log "Sample files cleaned"
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [clean|help]"
        echo ""
        echo "Commands:"
        echo "  clean    - Remove existing sample files"
        echo "  help     - Show this help message"
        echo ""
        echo "Running without arguments generates all sample files."
        ;;
    *)
        main
        ;;
esac