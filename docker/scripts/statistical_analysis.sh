#!/bin/bash

# Statistical Analysis Script for Load Test Results
# Calculates comprehensive statistics and generates reports

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="${PROJECT_ROOT}/docker-results"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Function to calculate statistics for a dataset
calculate_statistics() {
    local data=("$@")
    local n=${#data[@]}
    
    if [ $n -eq 0 ]; then
        echo "0,0,0,0,0,0"
        return
    fi
    
    # Calculate mean
    local sum=0
    for value in "${data[@]}"; do
        sum=$(echo "$sum + $value" | bc -l)
    done
    local mean=$(echo "scale=6; $sum / $n" | bc -l)
    
    # Calculate standard deviation
    local variance_sum=0
    for value in "${data[@]}"; do
        local diff=$(echo "$value - $mean" | bc -l)
        local squared=$(echo "$diff * $diff" | bc -l)
        variance_sum=$(echo "$variance_sum + $squared" | bc -l)
    done
    
    local variance=$(echo "scale=6; $variance_sum / $n" | bc -l)
    local stddev=$(echo "scale=6; sqrt($variance)" | bc -l)
    
    # Calculate coefficient of variation
    local cv=0
    if (( $(echo "$mean > 0" | bc -l) )); then
        cv=$(echo "scale=4; $stddev / $mean * 100" | bc -l)
    fi
    
    # Find min and max
    local min=${data[0]}
    local max=${data[0]}
    for value in "${data[@]}"; do
        if (( $(echo "$value < $min" | bc -l) )); then
            min=$value
        fi
        if (( $(echo "$value > $max" | bc -l) )); then
            max=$value
        fi
    done
    
    echo "$mean,$stddev,$cv,$min,$max,$n"
}

# Function to analyze single test results
analyze_test_results() {
    local test_id=$1
    local test_dir="$RESULTS_DIR/$test_id"
    
    if [ ! -d "$test_dir" ]; then
        warn "Test directory not found: $test_dir"
        return 1
    fi
    
    log "📊 Analyzing results for: $test_id"
    
    # Collect throughput and latency data from all runs
    local throughput_data=()
    local latency_data=()
    local error_rates=()
    
    for run_dir in "$test_dir"/run_*; do
        if [ -d "$run_dir" ] && [ -f "$run_dir/test_h2load.txt" ]; then
            local run_num=$(basename "$run_dir" | sed 's/run_//')
            
            # Skip run 1 if it should be discarded (warmup run)
            if [ "$run_num" = "1" ] && [ "${DISCARD_FIRST_RUN:-true}" = "true" ]; then
                info "   Skipping run 1 (warmup run)"
                continue
            fi
            
            # Extract metrics
            local throughput=$(grep "finished in.*req/s" "$run_dir/test_h2load.txt" | \
                sed -n 's/.*finished in [0-9.]*s, \([0-9.]*\) req\/s.*/\1/p' || echo "0")
            
            local avg_latency=$(grep "time for request:" "$run_dir/test_h2load.txt" | \
                awk '{print $6}' | sed 's/[^0-9.]//g' || echo "0")
            
            local total_requests=$(grep "requests:" "$run_dir/test_h2load.txt" | awk '{print $2}' || echo "0")
            local success_requests=$(grep "status codes:" "$run_dir/test_h2load.txt" | awk '{print $3}' || echo "0")
            
            local error_rate=0
            if [ "$total_requests" -gt 0 ]; then
                error_rate=$(echo "scale=4; (1 - $success_requests / $total_requests) * 100" | bc -l)
            fi
            
            if [ "$throughput" != "0" ]; then
                throughput_data+=("$throughput")
                latency_data+=("$avg_latency")
                error_rates+=("$error_rate")
                
                info "   Run $run_num: ${throughput} req/s, ${avg_latency}ms, ${error_rate}% errors"
            fi
        fi
    done
    
    if [ ${#throughput_data[@]} -eq 0 ]; then
        warn "No valid data found for $test_id"
        return 1
    fi
    
    # Calculate statistics
    local throughput_stats=($(calculate_statistics "${throughput_data[@]}"))
    local latency_stats=($(calculate_statistics "${latency_data[@]}"))
    local error_stats=($(calculate_statistics "${error_rates[@]}"))
    
    IFS=',' read -r tp_mean tp_stddev tp_cv tp_min tp_max tp_n <<< "${throughput_stats[0]}"
    IFS=',' read -r lat_mean lat_stddev lat_cv lat_min lat_max lat_n <<< "${latency_stats[0]}"
    IFS=',' read -r err_mean err_stddev err_cv err_min err_max err_n <<< "${error_stats[0]}"
    
    # Display results
    log "📈 Statistical Analysis for $test_id:"
    echo ""
    echo "   Throughput (req/s):"
    echo "     Mean: $(printf "%.2f" $tp_mean) ± $(printf "%.2f" $tp_stddev)"
    echo "     Range: $(printf "%.2f" $tp_min) - $(printf "%.2f" $tp_max)"
    echo "     CV: $(printf "%.2f" $tp_cv)%"
    echo ""
    echo "   Latency (ms):"
    echo "     Mean: $(printf "%.2f" $lat_mean) ± $(printf "%.2f" $lat_stddev)" 
    echo "     Range: $(printf "%.2f" $lat_min) - $(printf "%.2f" $lat_max)"
    echo "     CV: $(printf "%.2f" $lat_cv)%"
    echo ""
    echo "   Error Rate (%):"
    echo "     Mean: $(printf "%.4f" $err_mean)%"
    echo "     Range: $(printf "%.4f" $err_min)% - $(printf "%.4f" $err_max)%"
    echo ""
    
    # Assess consistency
    if (( $(echo "$tp_cv < 3.0" | bc -l) )); then
        log "✅ Excellent consistency (CV < 3%)"
    elif (( $(echo "$tp_cv < 5.0" | bc -l) )); then
        warn "⚠️  Good consistency (CV < 5%)"
    else
        warn "⚠️  Poor consistency (CV >= 5%) - consider more runs or longer warmup"
    fi
    
    # Save detailed results
    local summary_file="$test_dir/${test_id}_summary.csv"
    {
        echo "metric,mean,stddev,cv_percent,min,max,samples"
        echo "throughput_rps,$tp_mean,$tp_stddev,$tp_cv,$tp_min,$tp_max,$tp_n"
        echo "latency_ms,$lat_mean,$lat_stddev,$lat_cv,$lat_min,$lat_max,$lat_n"
        echo "error_rate_percent,$err_mean,$err_stddev,$err_cv,$err_min,$err_max,$err_n"
    } > "$summary_file"
    
    log "💾 Summary saved to: $summary_file"
    echo ""
}

# Function to generate comprehensive report
generate_comprehensive_report() {
    local report_file="$RESULTS_DIR/load_test_analysis_report.md"
    
    log "📄 Generating comprehensive analysis report..."
    
    {
        echo "# Load Test Analysis Report"
        echo "Generated: $(date)"
        echo ""
        
        echo "## Test Configuration"
        echo "- CPU Isolation: Enabled"
        echo "- Warmup Duration: 5 minutes"
        echo "- Test Duration: 15 minutes"
        echo "- Statistical Runs: 5 iterations"
        echo "- First Run: Discarded (warmup)"
        echo ""
        
        echo "## CPU Core Allocation"
        echo "| Component | CPU Cores | Constraint |"
        echo "|-----------|-----------|------------|"
        echo "| Passthrough | 0-1 | 2 cores |"
        echo "| Backend | 2-3 | 2 cores |"
        echo "| h2load | 4-7 | 4 cores |"
        echo ""
        
        echo "## Test Results Summary"
        echo ""
        
        # Find all test directories
        for test_dir in "$RESULTS_DIR"/*; do
            if [ -d "$test_dir" ] && [[ "$(basename "$test_dir")" =~ _.*users$ ]]; then
                local test_id=$(basename "$test_dir")
                
                if [ -f "$test_dir/${test_id}_summary.csv" ]; then
                    echo "### $test_id"
                    echo ""
                    
                    # Parse summary data
                    local tp_line=$(grep "^throughput_rps," "$test_dir/${test_id}_summary.csv")
                    local lat_line=$(grep "^latency_ms," "$test_dir/${test_id}_summary.csv")
                    
                    if [ -n "$tp_line" ] && [ -n "$lat_line" ]; then
                        IFS=',' read -r _ tp_mean tp_stddev tp_cv tp_min tp_max tp_n <<< "$tp_line"
                        IFS=',' read -r _ lat_mean lat_stddev lat_cv lat_min lat_max lat_n <<< "$lat_line"
                        
                        echo "| Metric | Mean | Std Dev | CV% | Min | Max |"
                        echo "|--------|------|---------|-----|-----|-----|"
                        echo "| Throughput (req/s) | $(printf "%.1f" $tp_mean) | $(printf "%.1f" $tp_stddev) | $(printf "%.1f" $tp_cv) | $(printf "%.1f" $tp_min) | $(printf "%.1f" $tp_max) |"
                        echo "| Latency (ms) | $(printf "%.1f" $lat_mean) | $(printf "%.1f" $lat_stddev) | $(printf "%.1f" $lat_cv) | $(printf "%.1f" $lat_min) | $(printf "%.1f" $lat_max) |"
                        echo ""
                        
                        # Consistency assessment
                        if (( $(echo "$tp_cv < 3.0" | bc -l) )); then
                            echo "**Consistency: ✅ Excellent (CV < 3%)**"
                        elif (( $(echo "$tp_cv < 5.0" | bc -l) )); then
                            echo "**Consistency: ⚠️ Good (CV < 5%)**"
                        else
                            echo "**Consistency: ❌ Poor (CV >= 5%)**"
                        fi
                        echo ""
                    fi
                fi
            fi
        done
        
        echo "## Consistency Analysis"
        echo ""
        echo "The Coefficient of Variation (CV) indicates result consistency:"
        echo "- **Excellent**: CV < 3% - Results are highly reproducible"
        echo "- **Good**: CV < 5% - Results are acceptably consistent" 
        echo "- **Poor**: CV >= 5% - Results show high variability"
        echo ""
        
        echo "## Recommendations"
        echo ""
        echo "For improved consistency:"
        echo "1. Ensure CPU cores are not oversaturated (monitor with \`./scripts/cpu_monitor.sh monitor\`)"
        echo "2. Increase warmup duration if CV > 5%"
        echo "3. Run more iterations for better statistical confidence"
        echo "4. Check system load and background processes"
        echo ""
        
    } > "$report_file"
    
    log "📋 Comprehensive report saved to: $report_file"
}

# Function to compare test configurations
compare_configurations() {
    log "🔍 Comparing test configurations..."
    
    local comparison_file="$RESULTS_DIR/configuration_comparison.csv"
    {
        echo "test_id,service,file_size,users,throughput_mean,throughput_cv,latency_mean,error_rate"
        
        for test_dir in "$RESULTS_DIR"/*; do
            if [ -d "$test_dir" ] && [[ "$(basename "$test_dir")" =~ _.*users$ ]]; then
                local test_id=$(basename "$test_dir")
                
                if [ -f "$test_dir/${test_id}_summary.csv" ]; then
                    # Parse test configuration
                    IFS='_' read -r service file_size users_part <<< "$test_id"
                    local users=$(echo "$users_part" | sed 's/users//')
                    
                    # Get metrics
                    local tp_line=$(grep "^throughput_rps," "$test_dir/${test_id}_summary.csv")
                    local lat_line=$(grep "^latency_ms," "$test_dir/${test_id}_summary.csv")
                    local err_line=$(grep "^error_rate_percent," "$test_dir/${test_id}_summary.csv")
                    
                    if [ -n "$tp_line" ] && [ -n "$lat_line" ]; then
                        IFS=',' read -r _ tp_mean _ tp_cv _ _ _ <<< "$tp_line"
                        IFS=',' read -r _ lat_mean _ _ _ _ _ <<< "$lat_line"
                        IFS=',' read -r _ err_mean _ _ _ _ _ <<< "$err_line"
                        
                        echo "$test_id,$service,$file_size,$users,$tp_mean,$tp_cv,$lat_mean,$err_mean"
                    fi
                fi
            fi
        done
    } > "$comparison_file"
    
    log "💾 Configuration comparison saved to: $comparison_file"
}

# Main execution
case "${1:-analyze}" in
    "analyze")
        if [ -n "$2" ]; then
            # Analyze specific test
            analyze_test_results "$2"
        else
            # Analyze all tests
            for test_dir in "$RESULTS_DIR"/*; do
                if [ -d "$test_dir" ] && [[ "$(basename "$test_dir")" =~ _.*users$ ]]; then
                    analyze_test_results "$(basename "$test_dir")"
                fi
            done
        fi
        ;;
    "report")
        generate_comprehensive_report
        ;;
    "compare")
        compare_configurations
        ;;
    "all")
        log "🚀 Running complete statistical analysis..."
        
        # Analyze all tests
        for test_dir in "$RESULTS_DIR"/*; do
            if [ -d "$test_dir" ] && [[ "$(basename "$test_dir")" =~ _.*users$ ]]; then
                analyze_test_results "$(basename "$test_dir")"
            fi
        done
        
        # Generate reports
        generate_comprehensive_report
        compare_configurations
        
        log "✅ Complete analysis finished!"
        ;;
    *)
        echo "Usage: $0 {analyze [test_id]|report|compare|all}"
        echo ""
        echo "Commands:"
        echo "  analyze [test_id] - Analyze specific test or all tests"
        echo "  report           - Generate comprehensive markdown report"
        echo "  compare          - Generate configuration comparison CSV"
        echo "  all              - Run complete analysis and generate all reports"
        exit 1
        ;;
esac