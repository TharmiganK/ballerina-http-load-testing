# Docker-Based Load Testing with CPU Isolation

This directory contains a comprehensive Docker-based load testing solution that ensures consistent, repeatable results by isolating components using explicit CPU core assignments and resource constraints.

## 🎯 Objective

Minimize CPU contention between the h2load client, Passthrough service, and Backend service running on a single machine through precise resource allocation and statistical analysis.

## 🏗️ Architecture

### Resource Allocation Strategy

| Component | CPU Cores | Implementation |
|-----------|-----------|----------------|
| Passthrough Service | 0-1 | Applied via `docker update --cpuset-cpus="0,1"` |
| Backend Service | 2-3 | Applied via `docker update --cpuset-cpus="2,3"` |
| h2load Client | 4-7 | Applied via `docker update --cpuset-cpus="4,5,6,7"` |

### Enhanced Test Parameters

- **Warmup Period**: 5 minutes (increased from 2 minutes)
- **Test Duration**: 15 minutes (increased from 10 minutes)  
- **Concurrent Users**: 100 (reduced from 200 to prevent CPU oversaturation)
- **Statistical Runs**: 5 iterations
- **First Run**: Discarded (warmup outlier)
- **Target Consistency**: CV < 3% for excellent results

## 📁 Directory Structure

```text
docker/
├── docker-compose.yml          # Main orchestration file
├── passthrough/
│   └── Dockerfile             # Ballerina service container
├── backend/
│   └── Dockerfile             # Netty backend container
└── h2load/
    └── Dockerfile             # Load generator container
```

## 🚀 Quick Start

### 1. Prerequisites

- Docker and Docker Compose installed
- Minimum 8 CPU cores (4 cores minimum for basic operation)
- Built Ballerina and Netty projects

### 2. Check System Requirements

```bash
./scripts/cpu_monitor.sh check
```

### 3. Build Docker Images

```bash
./scripts/docker_load_test.sh build
```

### 4. Run Statistical Load Tests

```bash
# Run default test suite (recommended configurations)
./scripts/docker_load_test.sh test

# Custom configuration
./scripts/docker_load_test.sh test -s "h1c-h1c,h2c-h2c" -f "1KB,10KB" -u "50,100" -r 3
```

### 5. Monitor CPU Usage (Optional)

```bash
# Monitor CPU usage during tests
./scripts/cpu_monitor.sh monitor 900
```

### 6. Analyze Results

```bash
# Complete statistical analysis
./scripts/statistical_analysis.sh all
```

## 🔧 Configuration Options

### Docker Load Test Script

```bash
./scripts/docker_load_test.sh [COMMAND] [OPTIONS]
```

**Commands:**

- `build` - Build Docker images
- `test` - Run load tests (default)
- `cleanup` - Stop containers and cleanup

**Options:**

- `-s, --services` - Service configurations (e.g., "h1c-h1c,h2c-h2c")
- `-f, --files` - File sizes (e.g., "1KB,10KB,100KB")
- `-u, --users` - Concurrent user counts (e.g., "50,100")
- `-r, --runs` - Number of statistical runs (default: 5)
- `-w, --warmup` - Warmup duration in seconds (default: 300)
- `-d, --duration` - Test duration in seconds (default: 900)
- `--no-discard` - Keep results from first run

### CPU Monitor Script

```bash
./scripts/cpu_monitor.sh {check|monitor|validate|affinity|report}
```

### Statistical Analysis Script

```bash
./scripts/statistical_analysis.sh {analyze|report|compare|all}
```

## 📊 Statistical Analysis

### Key Metrics

1. **Throughput (req/s)**
   - Mean ± Standard Deviation
   - Coefficient of Variation (CV)
   - Min/Max values

2. **Latency (ms)**
   - Average response time
   - Variability analysis

3. **Error Rate (%)**
   - Failed request percentage

### Consistency Assessment

- **Excellent**: CV < 3% - Highly reproducible results
- **Good**: CV < 5% - Acceptably consistent results  
- **Poor**: CV ≥ 5% - High variability, needs improvement

### Output Files

```text
docker-results/
├── [test_id]/
│   ├── run_1/ ... run_5/          # Individual run data
│   ├── [test_id]_summary.csv      # Statistical summary
│   └── cpu_usage.csv              # CPU monitoring data
├── load_test_analysis_report.md    # Comprehensive report
├── configuration_comparison.csv    # Cross-test comparison
└── system_resource_report.md       # System information
```

## 🎯 Example Workflows

### Basic Consistency Testing

```bash
# Quick consistency validation
./scripts/docker_load_test.sh test \
  -s "h1c-h1c" -f "1KB" -u "50" -r 3 -w 120 -d 300

# Analyze results
./scripts/statistical_analysis.sh analyze h1c-h1c_1KB_50users
```

### Full Protocol Comparison

```bash
# Compare HTTP/1.1 vs HTTP/2 performance
./scripts/docker_load_test.sh test \
  -s "h1c-h1c,h2c-h2c,h1c-h2c" -f "1KB,10KB,100KB" -u "100"

# Generate comprehensive analysis
./scripts/statistical_analysis.sh all
```

### Custom Resource Allocation

For systems with different CPU configurations, modify `docker-compose.yml`:

```yaml
# For 6-core systems
passthrough:
  cpuset: "0,1"
backend:
  cpuset: "2,3"  
h2load:
  cpuset: "4,5"
```

## 🔍 Monitoring and Validation

### CPU Usage Monitoring

The system automatically monitors CPU usage per container and alerts if usage exceeds 90%. Monitor results with:

```bash
# Real-time monitoring
./scripts/cpu_monitor.sh monitor 300

# Check container CPU affinity
./scripts/cpu_monitor.sh affinity

# Validate isolation effectiveness  
./scripts/cpu_monitor.sh validate docker-results/cpu_monitoring.csv
```

### Result Validation

Each test run includes:

- CPU usage validation
- Statistical confidence intervals
- Consistency metrics (CV analysis)
- Error rate monitoring

## 🚨 Troubleshooting

### High CPU Utilization

If total CPU usage exceeds 90%:

1. Reduce concurrent users (`-u` parameter)
2. Check for background processes
3. Verify CPU core allocation
4. Consider reducing test load

### Poor Consistency (CV > 5%)

1. Increase warmup duration (`-w` parameter)
2. Run more iterations (`-r` parameter)  
3. Check system stability
4. Verify resource isolation

### Container Issues

```bash
# Check container status
docker compose -f docker/docker-compose.yml ps

# View container logs
docker compose -f docker/docker-compose.yml logs

# Restart services
./scripts/docker_load_test.sh cleanup
./scripts/docker_load_test.sh build
```

## 📈 Performance Expectations

### Target Results (100 concurrent users, 1KB payload)

| Configuration | Expected Throughput | Target CV |
|---------------|-------------------|-----------|
| h1c-h1c | ~15,000 req/s | < 3% |
| h2c-h2c | ~20,000 req/s | < 3% |
| h1c-h2c | ~18,000 req/s | < 3% |

**Note:** Actual results depend on hardware specifications

## 🔗 Integration

### Continuous Integration

The Docker-based setup is ideal for CI/CD pipelines:

```yaml
# GitHub Actions example
- name: Run Load Tests
  run: |
    ./scripts/cpu_monitor.sh check
    ./scripts/docker_load_test.sh build
    ./scripts/docker_load_test.sh test -r 3 -w 120 -d 300
    ./scripts/statistical_analysis.sh all
```

### Performance Regression Detection

Use statistical thresholds to detect performance regressions:

```bash
# Set performance baselines
baseline_throughput=15000
current_throughput=$(grep "throughput_mean" results/*/summary.csv | awk -F',' '{print $2}')

# Alert if performance drops > 5%
threshold=$(echo "$baseline_throughput * 0.95" | bc -l)
if (( $(echo "$current_throughput < $threshold" | bc -l) )); then
    echo "Performance regression detected!"
fi
```

## 📝 Best Practices

1. **Always run warmup period** - Ensures JVM optimization and service stabilization
2. **Monitor CPU usage** - Verify isolation effectiveness
3. **Discard first run** - Eliminates warmup outliers
4. **Use multiple iterations** - Provides statistical confidence
5. **Check consistency metrics** - CV < 3% indicates reliable results
6. **Document system configuration** - Hardware specs affect results

## 🤝 Contributing

When adding new test configurations:

1. Update Docker resource constraints if needed
2. Add statistical validation
3. Document expected performance characteristics
4. Test on multiple hardware configurations
