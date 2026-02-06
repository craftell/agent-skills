#!/bin/bash
#
# just-do-it.sh - Run jdi workflow in a loop until completion
#
# Usage:
#   ./just-do-it.sh [options]
#
# Options:
#   -m, --max-iterations N   Maximum iterations (default: 100, 0 = unlimited)
#   -w, --workflow NAME      Workflow name or path (optional)
#   -t, --task ID            Specific task ID (optional)
#   -s, --stop-on-complete   Stop after current task completes
#   -v, --verbose            Show detailed output
#   -h, --help               Show this help message
#
# Examples:
#   ./just-do-it.sh                          # Run with defaults (max 100 iterations)
#   ./just-do-it.sh -m 50                    # Run with max 50 iterations
#   ./just-do-it.sh -m 0                     # Run unlimited until COMPLETE/ABORT
#   ./just-do-it.sh -w code-review -t 123    # Run specific workflow and task
#

set -euo pipefail

# Default configuration
MAX_ITERATIONS=100
WORKFLOW=""
TASK_ID=""
STOP_ON_COMPLETE=""
VERBOSE=false
STATUS_FILE=".jdi/status"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Show help
show_help() {
    sed -n '2,/^$/p' "$0" | sed 's/^#//; s/^ //'
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--max-iterations)
                MAX_ITERATIONS="$2"
                shift 2
                ;;
            -w|--workflow)
                WORKFLOW="$2"
                shift 2
                ;;
            -t|--task)
                TASK_ID="$2"
                shift 2
                ;;
            -s|--stop-on-complete)
                STOP_ON_COMPLETE="--stop-on-complete"
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use -h or --help for usage information."
                exit 1
                ;;
        esac
    done
}

# Build the jdi command
build_command() {
    local cmd="/jdi run"

    [[ -n "$WORKFLOW" ]] && cmd="$cmd --workflow $WORKFLOW"
    [[ -n "$TASK_ID" ]] && cmd="$cmd --task $TASK_ID"
    [[ -n "$STOP_ON_COMPLETE" ]] && cmd="$cmd $STOP_ON_COMPLETE"

    echo "$cmd"
}

# Read status from file
read_status() {
    if [[ -f "$STATUS_FILE" ]]; then
        cat "$STATUS_FILE" 2>/dev/null || echo "ABORT"
    else
        echo "ABORT"
    fi
}

# Main execution loop
main() {
    parse_args "$@"

    local cmd
    cmd=$(build_command)

    log_info "Starting jdi loop"
    log_info "Max iterations: ${MAX_ITERATIONS:-unlimited}"
    log_info "Command: claude -p \"$cmd\""
    echo ""

    local iteration=0
    local start_time
    start_time=$(date +%s)

    while true; do
        iteration=$((iteration + 1))

        # Check max iterations (0 = unlimited)
        if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $iteration -gt $MAX_ITERATIONS ]]; then
            log_warn "Max iterations ($MAX_ITERATIONS) reached"
            echo ""
            log_info "Summary: Stopped after $((iteration - 1)) iterations"
            exit 2
        fi

        # Show iteration header
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info "Iteration $iteration${MAX_ITERATIONS:+/$MAX_ITERATIONS}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # Execute jdi
        local iter_start
        iter_start=$(date +%s)

        if $VERBOSE; then
            claude -p "$cmd"
        else
            claude -p "$cmd" 2>&1 | tail -20
        fi

        local iter_end
        iter_end=$(date +%s)
        local iter_duration=$((iter_end - iter_start))

        # Read status
        local status
        status=$(read_status)

        log_info "Status: $status (took ${iter_duration}s)"
        echo ""

        # Handle status
        case $status in
            CONTINUE)
                log_ok "Continuing to next iteration..."
                echo ""
                ;;
            COMPLETE)
                local total_time=$(($(date +%s) - start_time))
                echo ""
                log_ok "Workflow completed successfully!"
                log_info "Total iterations: $iteration"
                log_info "Total time: ${total_time}s"
                exit 0
                ;;
            ABORT)
                local total_time=$(($(date +%s) - start_time))
                echo ""
                log_error "Workflow aborted!"
                log_info "Failed at iteration: $iteration"
                log_info "Total time: ${total_time}s"
                log_info "Check .jdi/reports/ for details"
                exit 1
                ;;
            *)
                log_error "Unknown status: $status"
                exit 1
                ;;
        esac
    done
}

# Run main
main "$@"
