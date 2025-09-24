# Ballerina HTTP Load Testing Framework

A comprehensive load testing framework for Ballerina HTTP passthrough services with configurable SSL and HTTP versions.

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
│   ├── 5KB.txt                     # Small payload
│   └── 10KB.txt                    # Large payload
├── scripts/                        # Test automation scripts
│   ├── run_load_tests.sh           # Main load testing orchestrator
│   ├── quick_test.sh               # Individual service testing
│   ├── validate_setup.sh           # Environment validation
│   ├── clean_results.sh            # Result cleanup utility
│   └── generate_samples.sh         # Sample file generator
├── passthrough-test-simple.jmx     # JMeter test plan
├── .gitignore                      # Git ignore rules
└── README.md                       # This file
```

## Service Configurations

The unified Ballerina service supports four different configurations through runtime parameters:

| Service | Client SSL | Server SSL | Port | Description |
|---------|------------|------------|------|-------------|
| h1-h1   | ✓          | ✓          | 9091 | HTTPS client → HTTPS server |
| h1c-h1  | ✗          | ✓          | 9092 | HTTP client → HTTPS server |
| h1-h1c  | ✓          | ✗          | 9093 | HTTPS client → HTTP server |
| h1c-h1c | ✗          | ✗          | 9094 | HTTP client → HTTP server |

## Prerequisites

- **Ballerina**: Swan Lake Update 8 or later
- **Maven**: 3.6.x or later (for building the Netty backend)
- **JMeter**: 5.x or later
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

3. **Run full load tests** (all 4 configurations):

   ```bash
   ./scripts/run_load_tests.sh
   ```

4. **Run specific service test**:

   ```bash
   ./scripts/quick_test.sh h1-h1 5KB.txt 100 30s
   ```

## Usage

### Full Load Testing

The main orchestrator script tests all four service configurations:

```bash
./scripts/run_load_tests.sh [OPTIONS]

Options:
  -u, --users NUM        Number of concurrent users (default: 100)
  -d, --duration TIME    Test duration (default: 30s)
  -f, --file SIZE        Payload file (5KB.txt or 10KB.txt, default: 5KB.txt)
  -w, --wait SECONDS     Wait time between service restarts (default: 5)
  -c, --clean           Clean previous results before starting
  --no-build            Skip Ballerina build step
  --debug               Enable debug output
  -h, --help            Show help
```

Example:

```bash
./scripts/run_load_tests.sh -u 200 -d 60s -f 10KB.txt -w 10 -c
```

### Individual Service Testing

Test a specific service configuration:

```bash
./scripts/quick_test.sh <service> <file> <users> <duration>

Parameters:
  service: h1-h1, h1c-h1, h1-h1c, or h1c-h1c
  file:    5KB.txt or 10KB.txt
  users:   Number of concurrent users
  duration: Test duration (e.g., 30s, 2m)
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
3. **Load Testing**: Execute JMeter test plan
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

- `results/`: Raw JMeter result files (`.jtl`)
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

1. **Modify JMeter Plan**: Edit `passthrough-test-simple.jmx`
2. **Add New Payloads**: Place files in `samples/` directory
3. **Update Scripts**: Modify configuration arrays in shell scripts

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

3. **JMeter Not Found**:

   ```bash
   # macOS with Homebrew
   brew install jmeter
   
   # Or download from https://jmeter.apache.org/
   ```

### Debug Mode

Enable debug output for detailed logging:

```bash
./scripts/run_load_tests.sh --debug
```

### Log Files

- Service logs: `results/` directory
- JMeter logs: Included in HTML reports

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
