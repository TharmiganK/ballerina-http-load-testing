# Ballerina HTTP Load Testing Framework

[![Load Tests](https://github.com/TharmiganK/ballerina-http-load-testing/actions/workflows/load-tests.yml/badge.svg)](https://github.com/TharmiganK/ballerina-http-load-testing/actions/workflows/load-tests.yml)

A comprehensive load testing framework for Ballerina HTTP passthrough services with configurable SSL and **HTTP/2** support.

> - **📋 Migration Note**: This framework has been updated to use **h2load** instead of JMeter for better performance, easier installation, and faster CI/CD execution.
> - **🚀 NEW**: HTTP/2 support added! The framework now supports **16 service configurations** including pure HTTP/2, mixed HTTP/1.1↔HTTP/2 scenarios, and comprehensive protocol comparisons.

## Features

- ✅ **HTTP/1.1 and HTTP/2 Support**: Test both protocols in all combinations
- ✅ **SSL/TLS Support**: HTTPS and clear text variants for all configurations  
- ✅ **Mixed Protocol Scenarios**: Test HTTP/1.1 clients with HTTP/2 backends and vice versa
- ✅ **Flexible Test Configuration**: Customize file sizes, user counts, services, and test duration
- ✅ **Comprehensive Payload Range**: From 50B to 1MB payloads for overhead analysis
- ✅ **Performance Comparison**: Compare protocol versions and identify bottlenecks
- ✅ **h2load Integration**: Modern HTTP/2 benchmarking with terminal output visibility
- ✅ **Automated Workflows**: GitHub Actions integration with configurable versions
- ✅ **Comprehensive Reporting**: Simplified CSV reports and detailed logs

## Project Structure

```bash
├── ballerina-passthrough/          # Unified Ballerina passthrough service
│   ├── Ballerina.toml              # Project configuration  
│   └── main.bal                    # Configurable HTTP service
├── netty-backend/                  # Backend service Maven project
│   ├── pom.xml                     # Maven configuration
│   ├── src/                        # Java source code
│   └── target/                     # Build output (including JAR)
├── resources/                      # SSL certificates and keys
│   ├── ballerinaKeystore.p12       # Keystore for HTTPS
│   └── ballerinaTruststore.p12     # Truststore for HTTPS
├── samples/                        # Test payload files
│   ├── 50B.txt                     # Minimal payload (50 bytes)
│   ├── 1KB.txt                     # Small payload (1 kilobyte)
│   ├── 5KB.txt                     # Medium payload
│   ├── 10KB.txt                    # Medium-large payload
│   ├── 100KB.txt                   # Large payload
│   ├── 500KB.txt                   # Very large payload
│   └── 1MB.txt                     # Maximum payload
├── scripts/                        # Test automation scripts
│   ├── run_load_tests.sh           # Main load testing orchestrator
│   ├── quick_test.sh               # Individual service testing
│   ├── validate_setup.sh           # Environment validation
│   ├── clean_results.sh            # Result cleanup utility
│   └── generate_samples.sh         # Sample file generator
├── .gitignore                      # Git ignore rules
└── README.md                       # This file
```

## Service Configurations

The unified Ballerina service now supports **16 different configurations** combining HTTP/1.1, HTTP/2, SSL, and clear text variants:

### HTTP/1.1 Configurations (Original)

| Service | Client | Server | Backend | Port | Description |
|---------|---------|---------|----------|------|-------------|
| h1-h1   | HTTP/1.1+SSL | HTTP/1.1+SSL | HTTP/1.1+SSL | 9091 | Pure HTTPS/1.1 |
| h1c-h1  | HTTP/1.1+SSL | HTTP/1.1 | HTTP/1.1+SSL | 9092 | Mixed SSL client |
| h1-h1c  | HTTP/1.1+SSL | HTTP/1.1+SSL | HTTP/1.1 | 9093 | Mixed SSL backend |
| h1c-h1c | HTTP/1.1 | HTTP/1.1 | HTTP/1.1 | 9094 | Pure HTTP/1.1 |

### HTTP/2 Configurations (New)

| Service | Client | Server | Backend | Port | Description |
|---------|---------|---------|----------|------|-------------|
| h2-h2   | HTTP/2+SSL | HTTP/2+SSL | HTTP/2+SSL | 9095 | Pure HTTPS/2 |
| h2c-h2  | HTTP/2+SSL | HTTP/2 | HTTP/2+SSL | 9096 | Mixed SSL client |
| h2-h2c  | HTTP/2+SSL | HTTP/2+SSL | HTTP/2 | 9097 | Mixed SSL backend |
| h2c-h2c | HTTP/2 | HTTP/2 | HTTP/2 | 9098 | Pure HTTP/2 clear text |

### Mixed HTTP/1.1 Client → HTTP/2 Backend (New)

| Service | Client | Server | Backend | Port | Description |
|---------|---------|---------|----------|------|-------------|
| h1-h2   | HTTP/1.1+SSL | HTTP/1.1+SSL | HTTP/2+SSL | 9099 | H1.1→H2 with SSL |
| h1c-h2  | HTTP/1.1+SSL | HTTP/1.1 | HTTP/2+SSL | 9100 | H1.1→H2 mixed SSL |
| h1-h2c  | HTTP/1.1+SSL | HTTP/1.1+SSL | HTTP/2 | 9101 | H1.1→H2 clear backend |
| h1c-h2c | HTTP/1.1 | HTTP/1.1 | HTTP/2 | 9102 | H1.1→H2 clear text |

### Mixed HTTP/2 Client → HTTP/1.1 Backend (New)

| Service | Client | Server | Backend | Port | Description |
|---------|---------|---------|----------|------|-------------|
| h2-h1   | HTTP/2+SSL | HTTP/2+SSL | HTTP/1.1+SSL | 9103 | H2→H1.1 with SSL |
| h2c-h1  | HTTP/2+SSL | HTTP/2 | HTTP/1.1+SSL | 9104 | H2→H1.1 mixed SSL |
| h2-h1c  | HTTP/2+SSL | HTTP/2+SSL | HTTP/1.1 | 9105 | H2→H1.1 clear backend |
| h2c-h1c | HTTP/2 | HTTP/2 | HTTP/1.1 | 9106 | H2→H1.1 clear text |

**Naming Convention**: `{client_protocol}-{backend_protocol}` where:

- **h1** = HTTP/1.1 with SSL, **h1c** = HTTP/1.1 clear text
- **h2** = HTTP/2 with SSL, **h2c** = HTTP/2 clear text

## Prerequisites

- **Ballerina**: Swan Lake Update 8 or later
- **Maven**: 3.6.x or later (for building the Netty backend)
- **h2load**: HTTP/2 benchmarking tool (part of nghttp2)
- **Java**: 11 or later (for running JAR files)
- **macOS/Linux**: For shell script execution

## Quick Start

1. **Clone the repository**:

   ```bash
   git clone https://github.com/TharmiganK/ballerina-http-load-testing.git
   cd ballerina-http-load-testing
   ```

2. **Validate environment**:

   ```bash
   ./scripts/validate_setup.sh
   ```

3. **Try the HTTP/2 demo** (interactive):

   ```bash
   ./scripts/http2_demo.sh
   ```

4. **Run full load tests** (all 16 configurations):

   ```bash
   ./scripts/run_load_tests.sh
   ```

5. **Test specific configurations**:

   ```bash
   # Test pure HTTP/2 with SSL
   ./scripts/quick_test.sh h2-h2 1KB 10 5
   
   # Test mixed HTTP/1.1 → HTTP/2 scenario
   ./scripts/quick_test.sh h1-h2c 10KB 50 30
   
   # Compare HTTP/1.1 vs HTTP/2 performance
   ./scripts/quick_test.sh h1c-h1c 1KB 100 60  # Baseline HTTP/1.1
   ./scripts/quick_test.sh h2c-h2c 1KB 100 60  # HTTP/2 equivalent
   
   # Test with new 50B payload for minimal overhead testing
   ./scripts/quick_test.sh h2-h2 50B 25 15
   ```

6. **Use advanced load testing options**:

   ```bash
   # Test specific services with custom parameters
   ./scripts/run_load_tests.sh --services "h2-h2,h2c-h2c" --files "50B,1KB" --users "50,100"
   
   # Quick performance comparison
   ./scripts/run_load_tests.sh -s "h1c-h1c,h2c-h2c" -f "1KB" -u "100" -d 120
   ```

## HTTP/2 Performance Testing

The framework enables comprehensive HTTP/2 performance analysis:

### Protocol Comparison Scenarios

- **Pure Protocol Tests**: Compare h1-h1 vs h2-h2 (SSL) or h1c-h1c vs h2c-h2c (clear text)
- **Mixed Protocol Impact**: Test h1-h2 vs h2-h1 to understand protocol translation overhead
- **Migration Path Testing**: Evaluate h1-h1 → h1-h2 → h2-h2 upgrade scenarios

### Expected Performance Benefits

- **HTTP/2 Multiplexing**: Better performance under high concurrency
- **Header Compression**: HPACK reduces overhead for repeated headers
- **Binary Protocol**: More efficient parsing than HTTP/1.1 text format

📖 **Detailed HTTP/2 Documentation**: See [HTTP2_EXTENSION.md](HTTP2_EXTENSION.md) for complete configuration matrix, usage patterns, and performance tuning guidance.

## Usage

### Full Load Testing

The main orchestrator script supports comprehensive customization for all 16 service configurations:

```bash
./scripts/run_load_tests.sh [COMMAND] [OPTIONS]

Commands:
  build               Build both Netty backend and Ballerina projects
  build-backend       Build only the Netty backend Maven project  
  build-ballerina     Build only the Ballerina project
  start-backend       Build and start all netty backends for manual testing
  test                Run load testing suite (default command)
  reports             Generate HTML reports from existing results
  cleanup             Stop all services and clean up processes
  clean               Clean test results and reports
  help, -h, --help    Show detailed help message

Test Options (for 'test' command):
  -f, --file-sizes, --files SIZES    Comma-separated file sizes (e.g., "1KB,10KB,100KB")
  -u, --users USERS                  Comma-separated user counts (e.g., "50,100,500")
  -s, --services SERVICES            Comma-separated service names (e.g., "h1-h1,h2-h2")
  -d, --duration SECONDS             Test duration in seconds (default: 300)
  -h, --help                         Show help message

Available Services:
  h1-h1 h1c-h1 h1-h1c h1c-h1c h2-h2 h2c-h2 h2-h2c h2c-h2c 
  h1-h2 h1c-h2 h1-h2c h1c-h2c h2-h1 h2c-h1 h2-h1c h2c-h1c

Available File Sizes:
  Any valid format like: 50B, 1KB, 5KB, 10KB, 100KB, 500KB, 1MB

Default Parameters:
  File sizes: 50B, 1KB, 10KB, 100KB, 500KB, 1MB
  Users: 50, 100, 500
  Services: All 16 configurations
  Duration: 300 seconds (5 minutes per test)
```

**Examples:**

```bash
# Run complete test suite with defaults
./scripts/run_load_tests.sh

# Test specific services only
./scripts/run_load_tests.sh test --services "h1-h1,h2-h2,h2c-h2c"

# Test with specific file sizes and user counts
./scripts/run_load_tests.sh test -f "1KB,100KB" -u "50,200"

# Quick HTTP/2 comparison test
./scripts/run_load_tests.sh --services "h1c-h1c,h2c-h2c" --files "1KB" --users "100" --duration 120

# Test mixed protocol scenarios
./scripts/run_load_tests.sh test -s "h1-h2,h2-h1" -f "10KB,100KB" -u "50,100"

# Use short options for concise commands
./scripts/run_load_tests.sh -s "h2-h2" -f "50B,1KB" -u "25,50" -d 60
```

### Individual Service Testing

Test a specific service configuration:

```bash
./scripts/quick_test.sh <service> <file> <users> <duration>

Parameters:
  service: Any of the 16 available services (h1-h1, h1c-h1, h1-h1c, h1c-h1c, h2-h2, etc.)
  file:    Any available payload file (50B, 1KB, 5KB, 10KB, 100KB, 500KB, 1MB)
  users:   Number of concurrent users
  duration: Test duration in seconds
```

Examples:

```bash
# Test HTTP/2 with minimal payload
./scripts/quick_test.sh h2-h2 50B 25 30

# Compare HTTP/1.1 vs HTTP/2 with same parameters  
./scripts/quick_test.sh h1c-h1c 1KB 100 60
./scripts/quick_test.sh h2c-h2c 1KB 100 60

# Test mixed protocol scenario
./scripts/quick_test.sh h1-h2 10KB 50 120
```

### Environment Validation

Check if all required tools and files are present:

```bash
./scripts/validate_setup.sh
```

### Results Management

Clean test results and reports:

```bash
./scripts/clean_results.sh [all|results|reports]
```

## Advanced Testing Scenarios

The enhanced argument system enables sophisticated testing scenarios:

### Performance Comparison Testing

```bash
# Compare HTTP/1.1 vs HTTP/2 clear text performance
./scripts/run_load_tests.sh --services "h1c-h1c,h2c-h2c" --files "1KB,10KB" --users "100"

# Test protocol translation overhead  
./scripts/run_load_tests.sh -s "h1-h1,h1-h2,h2-h1,h2-h2" -f "10KB" -u "100" -d 180
```

### Load Progression Testing

```bash
# Test scalability with increasing load
./scripts/run_load_tests.sh --services "h2-h2" --files "1KB" --users "50,100,200,500"

# Payload size impact analysis
./scripts/run_load_tests.sh -s "h2c-h2c" -u "100" -f "50B,1KB,10KB,100KB,1MB"
```

### Targeted Protocol Analysis

```bash
# Test all HTTP/2 configurations
./scripts/run_load_tests.sh --services "h2-h2,h2c-h2,h2-h2c,h2c-h2c" --files "1KB,100KB"

# Mixed protocol scenarios only
./scripts/run_load_tests.sh -s "h1-h2,h1c-h2,h1-h2c,h1c-h2c,h2-h1,h2c-h1,h2-h1c,h2c-h1c"
```

### Quick Development Testing

```bash  
# Fast iteration testing (short duration, minimal load)
./scripts/run_load_tests.sh -s "h1-h1,h2-h2" -f "50B" -u "10" -d 30

# Comprehensive but focused testing
./scripts/run_load_tests.sh -s "h1c-h1c,h2c-h2c" -f "1KB,100KB" -u "50,100" -d 60
```

## How It Works

### Service Architecture

1. **Ballerina Service**: Acts as HTTP passthrough proxy
2. **Netty Backend**: Echo service that returns received payloads
3. **Runtime Configuration**: Service behavior controlled by runtime parameters:
   - `-CclientSsl=true/false`: Enable/disable SSL for backend calls
   - `-CserverSsl=true/false`: Enable/disable SSL for incoming requests
   - `-CserverPort=XXXX`: Set listening port

### Testing Process

1. **Build Phase**: Clean and build Ballerina project
2. **Service Startup**: Start Netty backend and Ballerina service
3. **Load Testing**: Execute h2load benchmarking
4. **Result Collection**: Generate reports and collect metrics
5. **Cleanup**: Stop services and prepare for next test

### Service Restart Strategy

Between each test scenario, services are completely restarted to ensure:

- Clean memory state
- No connection pooling effects
- Consistent baseline performance
- Isolated test results

## Results and Reports

### Directory Structure

- `results/`: Raw h2load result files (`.csv`)
- `reports/`: HTML reports with detailed metrics

### Key Metrics

- **Throughput**: Requests per second
- **Response Time**: Average, median, 90th, 95th, 99th percentiles
- **Error Rate**: Percentage of failed requests
- **Concurrent Users**: Load levels tested

## Development

### Building Ballerina Service

```bash
cd ballerina-passthrough
bal clean
rm -f Dependencies.toml  # Remove if exists
bal build
```

### SSL Configuration

The framework uses pre-configured SSL certificates:

- **Keystore**: `resources/ballerinaKeystore.p12` (password: ballerina)
- **Truststore**: `resources/ballerinaTruststore.p12` (password: ballerina)

### Extending Tests

1. **Custom h2load Options**: Modify script parameters
2. **Add New Payloads**: Place files in `samples/` directory
3. **Update Scripts**: Modify configuration arrays in shell scripts

## CI/CD Workflows

This repository includes automated GitHub workflows for continuous testing:

### Load Tests (`.github/workflows/load-tests.yml`)

Comprehensive load testing with configurable parameters:

**Triggers:**

- Manual dispatch with custom parameters

**Manual Workflow Parameters:**

- **Service Type**: Choose specific service or test all (any of the 16 services or `all`)
- **Payload Sizes**: Comma-separated list (`50B,1KB,10KB,100KB,500KB,1MB`)
- **User Counts**: Comma-separated list (`50,100,500`)  
- **Test Duration**: Duration in seconds (default: 300)

**Example Manual Runs:**

```bash
# Test all services with minimal overhead
Service Type: all
Payload Sizes: 50B,1KB  
User Counts: 25,50
Duration: 180

# HTTP/2 performance comparison
Service Type: h1c-h1c,h2c-h2c,h1-h2,h2-h1
Payload Sizes: 1KB,10KB,100KB
User Counts: 50,100,200
Duration: 300

# High load stress test  
Service Type: h2-h2,h2c-h2c
Payload Sizes: 100KB,500KB,1MB
User Counts: 100,500,1000
Duration: 300
```

**Workflow Outputs:**

- 📈 Individual test results (CSV format)
- 📊 Consolidated performance report
- 💬 Automated PR comments with results
- 🗄️ 90-day result retention

### Running Workflows

1. **Manual**: Go to Actions → Load Tests → Run workflow
2. **Results**: Download artifacts or view in workflow summary

## Troubleshooting

### Common Issues

1. **Port Already in Use**:

   ```bash
   # Kill processes using required ports
   pkill -f "netty-http-echo-service"
   pkill -f "ballerina_passthrough"
   ```

2. **Build Failures**:

   ```bash
   cd ballerina-passthrough
   bal clean
   rm -f Dependencies.toml
   bal build
   ```

3. **h2load Not Found**:

   ```bash
   # macOS with Homebrew
   brew install nghttp2
   
   # Ubuntu/Debian
   sudo apt-get install nghttp2-client
   ```

### Debug Mode

Enable debug output for detailed logging:

```bash
./scripts/run_load_tests.sh --debug
```

### Log Files

- Service logs: `results/` directory
- h2load logs: Included in HTML reports

## Demo

Run the interactive demo to see all features:

```bash
./scripts/demo.sh
```

This will:

- Validate your environment
- Build the Ballerina project  
- Run a sample load test
- Show cleanup functionality
- Provide usage examples

## Contributing

1. Fork the repository
2. Create feature branch
3. Test changes thoroughly
4. Submit pull request with detailed description

## License

This project is licensed under the MIT License.
