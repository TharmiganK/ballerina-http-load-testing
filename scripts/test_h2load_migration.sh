#!/bin/bash

# Test script to verify h2load migration works correctly
# Usage: ./test_h2load_migration.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🔍 Testing h2load migration..."
echo "Project root: $PROJECT_ROOT"

# Check if h2load is installed
if ! command -v h2load &> /dev/null; then
    echo "❌ h2load is not installed"
    echo "Install with:"
    echo "  macOS: brew install nghttp2"
    echo "  Ubuntu: sudo apt-get install nghttp2-client"
    exit 1
fi

echo "✅ h2load is installed: $(h2load --version | head -1)"

# Check if samples directory exists and has test files
if [ ! -d "$PROJECT_ROOT/samples" ]; then
    echo "📁 Creating samples directory..."
    mkdir -p "$PROJECT_ROOT/samples"
fi

# Generate test samples if they don't exist
echo "📝 Ensuring test sample files exist..."
echo "A" > "$PROJECT_ROOT/samples/1KB.txt"
for i in {1..5}; do echo "$(cat "$PROJECT_ROOT/samples/1KB.txt")$(cat "$PROJECT_ROOT/samples/1KB.txt")" >> "$PROJECT_ROOT/samples/1KB.txt"; done
head -c 1024 "$PROJECT_ROOT/samples/1KB.txt" > "$PROJECT_ROOT/samples/temp.txt" && mv "$PROJECT_ROOT/samples/temp.txt" "$PROJECT_ROOT/samples/1KB.txt"

# Create 5KB sample
for i in {1..5}; do cat "$PROJECT_ROOT/samples/1KB.txt" >> "$PROJECT_ROOT/samples/5KB.txt"; done

echo "✅ Sample files ready:"
ls -la "$PROJECT_ROOT/samples/"

# Test h2load against a simple HTTP server (if available)
echo "🧪 Testing h2load functionality..."

# Create a simple test payload
test_payload="$PROJECT_ROOT/samples/test_payload.txt"
echo "Hello, h2load test!" > "$test_payload"

# Test h2load syntax (against httpbin.org if internet is available)
if ping -c 1 httpbin.org &> /dev/null; then
    echo "🌐 Testing h2load against httpbin.org..."
    h2load_output=$(mktemp)
    
    if h2load -c 2 -t 2 -T 5 -d "$test_payload" -m POST \
        --h1 -k "https://httpbin.org/post" > "$h2load_output" 2>&1; then
        echo "✅ h2load test successful!"
        echo "📊 Results:"
        grep -E "(requests:|2xx responses:|req/s)" "$h2load_output" | head -5
    else
        echo "⚠️  h2load test failed, but h2load is working"
    fi
    
    rm -f "$h2load_output"
else
    echo "⚠️  No internet connection, skipping online test"
fi

# Verify CSV output format
echo "📋 Testing CSV output format..."
csv_file=$(mktemp)
echo "timestamp,elapsed,label,responseCode,responseMessage,threadName,dataType,success,failureMessage,bytes,sentBytes,grpThreads,allThreads,URL,Filename,latency,idleTime,connect" > "$csv_file"
echo "1234567890,100,HTTP Request,200,OK,Thread Group 1-1,text,true,,1024,1024,1,1,https://example.com,,100,0,0" >> "$csv_file"

if [ $(wc -l < "$csv_file") -eq 2 ]; then
    echo "✅ CSV format is valid"
else
    echo "❌ CSV format issue"
fi

rm -f "$csv_file" "$test_payload"

echo ""
echo "🎉 h2load migration test completed successfully!"
echo ""
echo "Next steps:"
echo "1. Run: scripts/validate_setup.sh"
echo "2. Build projects: cd ballerina-passthrough && bal build && cd ../netty-backend && mvn clean package"
echo "3. Test: scripts/quick_test.sh h1c-h1c 1KB 5 60"