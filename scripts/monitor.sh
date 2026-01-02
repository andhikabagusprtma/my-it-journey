#!/bin/bash
# NOC Monitoring Script - WSL2 Ubuntu
# Enhanced with Auto-Switch Diagnosis Mode
# Created: 2025-11-25 | Updated: 2026-01-01

# ========== CONFIG ==========
BASE_DIR="$HOME/my-it-journey"
LOG_DIR="$BASE_DIR/logs"
ALERT_DIR="$BASE_DIR/alerts"
DIAG_DIR="$BASE_DIR/diagnosis"

# ========== DEFAULT TARGETS ==========
DEFAULT_TARGETS=("8.8.8.8" "google.com" "1.1.1.1")
MAX_RETRIES=2
TIMEOUT=2

# ========== FLAPPING TEST CONFIG ==========
ENABLE_FLAPPING_TEST="true"
FLAPPING_MODE="time"
FAILURE_PROBABILITY=35
FLAPPING_INTERVAL=300

# ========== PARSE ARGUMENTS ==========
TARGETS=("${DEFAULT_TARGETS[@]}")

if [ $# -gt 0 ]; then
    TARGETS=("$@")
    echo "=== PROBLEM DETECTED ==="
fi

# ========== SETUP ==========
mkdir -p "$LOG_DIR" "$ALERT_DIR" "$DIAG_DIR"
LOG_FILE="$LOG_DIR/monitor-$(date +%Y%m%d).log"
ALERT_FILE="$ALERT_DIR/alerts-$(date +%Y%m%d).log"
DIAGNOSIS_FILE="$DIAG_DIR/diagnosis-$(date +%Y%m%d).log"

# ========== FUNCTIONS ==========
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE"
}

log_diagnosis() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DIAGNOSIS] $1" >> "$DIAGNOSIS_FILE"
}

create_alert() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ALERT] $1" >> "$ALERT_FILE"
    log_error "ALERT: $1"
}

# ========== AUTO-SWITCH DIAGNOSIS FUNCTIONS ==========
diagnose_network() {
    local target="$1"
    log_info "🔄 Switching to NETWORK diagnosis mode"

    log_diagnosis "NETWORK_DIAGNOSIS for $target"

    # 1. Check route
    if ip route get "$target" &>/dev/null 2>&1; then
        log_diagnosis "  ✅ Route exists to $target"
    else
        log_diagnosis "  ❌ NO ROUTE to $target"
    fi

    # 2. Check interface status
    if ip link show | grep -q "state UP"; then
        log_diagnosis "  ✅ Network interface is UP"
    else
        log_diagnosis "  ❌ Network interface is DOWN"
    fi

    # 3. Check gateway
    local gateway=$(ip route | grep default | head -1 | awk '{print $3}')
    if [ -n "$gateway" ]; then
        log_diagnosis "  ✅ Default gateway: $gateway"
        if ping -c 1 -W 1 "$gateway" &>/dev/null; then
            log_diagnosis "  ✅ Gateway $gateway is reachable"
        else
            log_diagnosis "  ❌ Gateway $gateway is UNREACHABLE"
        fi
    else
        log_diagnosis "  ❌ No default gateway configured"
    fi

    log_info "  📋 Network diagnosis saved"
}

diagnose_dns() {
    local domain="$1"
    log_info "🔄 Switching to DNS diagnosis mode"

    log_diagnosis "DNS_DIAGNOSIS for $domain"

    # 1. Check DNS servers
    if [ -f /etc/resolv.conf ]; then
        log_diagnosis "  DNS servers configured:"
        grep -i nameserver /etc/resolv.conf >> "$DIAGNOSIS_FILE"
    else
        log_diagnosis "  ❌ /etc/resolv.conf not found"
    fi

    # 2. Test with multiple DNS servers
    local dns_servers=("8.8.8.8" "1.1.1.1" "192.168.1.1")
    local dns_working=false

    for dns in "${dns_servers[@]}"; do
        if nslookup "$domain" "$dns" &>/dev/null 2>&1; then
            log_diagnosis "  ✅ DNS resolution SUCCESS with $dns"
            dns_working=true
            break
        fi
    done

    if ! $dns_working; then
        log_diagnosis "  ❌ DNS resolution FAILED with all servers"
    fi

    # 3. Check /etc/hosts
    if grep -q "$domain" /etc/hosts 2>/dev/null; then
        log_diagnosis "  ✅ Found in /etc/hosts"
    else
        log_diagnosis "  ❌ Not found in /etc/hosts"
    fi

    log_info "  📋 DNS diagnosis saved"
}

diagnose_interface() {
    local target="$1"
    log_diagnosis "=== INTERFACE DIAGNOSIS ==="

    if command -v ip &>/dev/null; then
        log_diagnosis "Network Interfaces:"
        ip -br link show | while read line; do
            log_diagnosis "  $line"
        done
    fi

    if ip link show | grep -q "state UP"; then
        log_diagnosis "✅ At least one interface is UP"
    else
        log_diagnosis "❌ All interfaces are DOWN"
    fi
}

diagnose_gateway() {
    local target="$1"
    log_diagnosis "=== GATEWAY DIAGNOSIS ==="

    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)

    if [ -n "$gateway" ]; then
        log_diagnosis "Default Gateway: $gateway"

        if ping -c 1 -W 2 "$gateway" &>/dev/null; then
            log_diagnosis "✅ Gateway is reachable"
        else
            log_diagnosis "❌ Gateway is NOT reachable"
        fi
    else
        log_diagnosis "❌ No default gateway configured"
    fi

    log_diagnosis "Routing Table:"
    ip route | grep -E "default|via" | head -3 | while read line; do
        log_diagnosis "  $line"
    done
}

# ========== FLAPPING TEST FUNCTIONS ==========
should_fail_now() {
    local current_epoch=$(date +%s)
    local interval=$FLAPPING_INTERVAL

    if [ $((current_epoch / interval % 2)) -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

should_fail_randomly() {
    local random=$((RANDOM % 100))
    if [ $random -lt $FAILURE_PROBABILITY ]; then
        return 0
    fi
    return 1
}

should_fail_by_pattern() {
    local minute=$(date +%M)

    if [[ $minute =~ ^[0-4]$ ]] || \
       [[ $minute =~ ^1[5-9]$ ]] || \
       [[ $minute =~ ^3[0-4]$ ]] || \
       [[ $minute =~ ^4[5-9]$ ]]; then
        return 0
    fi
    return 1
}

should_fail_persistent() {
    local STATE_FILE="$BASE_DIR/flapping-state.txt"
    local current_minute=$(date +%M)
    local last_state=$(cat "$STATE_FILE" 2>/dev/null | cut -d: -f1 || echo "normal")
    local last_minute=$(cat "$STATE_FILE" 2>/dev/null | cut -d: -f2 || echo "0")

    if [ $((current_minute / 5)) -ne $((last_minute / 5)) ]; then
        if [ "$last_state" = "normal" ]; then
            echo "failure:$current_minute" > "$STATE_FILE"
            return 0
        else
            echo "normal:$current_minute" > "$STATE_FILE"
            return 1
        fi
    else
        [ "$last_state" = "failure" ] && return 0 || return 1
    fi
}

# ========== SMART CHECK WITH AUTO-DIAGNOSIS ==========
smart_check() {
    local target="$1"
    local is_up=false
    local latency="N/A"
    local failed_attempts=0

    for ((i=1; i<=MAX_RETRIES; i++)); do
        if ping -c 1 -W $TIMEOUT "$target" &>/dev/null; then
            is_up=true
            if ping_result=$(ping -c 1 -W $TIMEOUT "$target" 2>&1); then
                if echo "$ping_result" | grep -q "time="; then
                    latency=$(echo "$ping_result" | grep "time=" | sed -E 's/.*time=([0-9.]+) ms.*/\1/')
                fi
            fi
            break
        else
            ((failed_attempts++))
            if [ $i -eq 1 ]; then
                log_info "  ⚠️  First attempt failed, starting quick diagnosis..."
            fi
            sleep 1
        fi
    done

    echo "$is_up:$latency:$failed_attempts"
}

# ========== MAIN ==========
log_info "========== 🛡️ NOC MONITOR STARTED =========="
log_info "Checking $(echo "${TARGETS[@]}" | wc -w) targets"
log_info "Targets: ${TARGETS[*]}"

# ========== FLAPPING TEST LOGIC ==========
if [ "$ENABLE_FLAPPING_TEST" = "true" ]; then
    log_info "🧪 Flapping test: $FLAPPING_MODE mode (enabled)"

    case "$FLAPPING_MODE" in
        "time")
            if should_fail_now; then
                log_info "⏰ [TIME-BASED TEST] Adding synthetic failure target"
                TARGETS+=("169.254.255.255")
            fi
            ;;
        "random")
            if should_fail_randomly; then
                log_info "🎲 [RANDOM TEST] Adding synthetic failure target"
                TARGETS+=("169.254.255.255")
            fi
            ;;
        "pattern")
            if should_fail_by_pattern; then
                log_info "📊 [PATTERN TEST] Adding synthetic failure target"
                TARGETS+=("169.254.255.255")
            fi
            ;;
        "persistent")
            if should_fail_persistent; then
                log_info "💾 [PERSISTENT TEST] Adding synthetic failure target"
                TARGETS+=("169.254.255.255")
            fi
            ;;
    esac

    log_info "Updated targets: ${TARGETS[*]}"
fi
# ========== END FLAPPING TEST ==========

ALL_UP=true
SUMMARY=""
DIAGNOSIS_TRIGGERED=false

for target in "${TARGETS[@]}"; do
    log_info "📡 Checking: $target"

    result=$(smart_check "$target")
    is_up=$(echo "$result" | cut -d: -f1)
    latency=$(echo "$result" | cut -d: -f2)
    failed_attempts=$(echo "$result" | cut -d: -f3)

    if [ "$is_up" = "true" ]; then
        if [ "$failed_attempts" -gt 0 ]; then
            log_info "  ✅ RECOVERED $target - Latency: ${latency}ms (after $failed_attempts attempts)"
        else
            log_info "  ✅ UP $target - Latency: ${latency}ms"
        fi
        SUMMARY+="✅ $target "
    else
        log_error "  ❌ DOWN $target"
        create_alert "$target is DOWN (ping failed after $MAX_RETRIES attempts)"
        ALL_UP=false
        SUMMARY+="❌ $target "

        DIAGNOSIS_TRIGGERED=true

        if [[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            diagnose_network "$target"
            diagnose_interface "$target"
            diagnose_gateway "$target"

            if grep -q "UNREACHABLE" "$DIAGNOSIS_FILE"; then
                log_info "  🚨 Gateway issue detected, triggering auto-remediation..."
                ~/my-it-journey/scripts/remediate.sh >> "$LOG_FILE" 2>&1
            fi
        else
            diagnose_dns "$target"
            diagnose_interface "$target"
            diagnose_gateway "$target"
        fi
    fi
done

# ========== FINAL REPORT ==========
log_info "========== 📊 FINAL REPORT =========="

if $ALL_UP; then
    if $DIAGNOSIS_TRIGGERED; then
        log_info "✅ STATUS: RECOVERED (transient issues detected)"
    else
        log_info "✅ STATUS: ALL SYSTEMS HEALTHY"
    fi
else
    log_error "❌ STATUS: DEGRADED - Check alerts & diagnosis"

    if [ -f "$DIAGNOSIS_FILE" ] && [ -s "$DIAGNOSIS_FILE" ]; then
        log_info "🔍 Diagnosis summary:"
        grep -E "(NETWORK_DIAGNOSIS|DNS_DIAGNOSIS|✅|❌)" "$DIAGNOSIS_FILE" | \
        tail -6 | while read line; do
            log_info "  $(echo "$line" | sed 's/\[DIAGNOSIS\]//')"
        done
    fi

    log_info "📋 Full diagnosis: $DIAGNOSIS_FILE"
    log_info "🚨 Alerts: $ALERT_FILE"
fi

# Cleanup old files
find "$ALERT_DIR" -name "alerts-*.log" -mtime +2 -delete 2>/dev/null
find "$DIAG_DIR" -name "diagnosis-*.log" -mtime +3 -delete 2>/dev/null

log_info "📝 Summary: $SUMMARY"
log_info "📂 Log saved to: $LOG_FILE"
log_info "========== 🛡️ MONITOR COMPLETE =========="
