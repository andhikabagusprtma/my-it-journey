#!/bin/bash
# NOC Auto-Remediation - WSL2 Focus
# Safe remediation for gateway issues
# Updated: 2026-01-01

# ========== CONFIG ==========
BASE_DIR="$HOME/my-it-journey"
LOG_DIR="$BASE_DIR/logs"
SCRIPT_DIR="$BASE_DIR/scripts"
LOG_FILE="$LOG_DIR/remediation-$(date +%Y%m%d).log"
LOCK_FILE="/tmp/noc-remediation.lock"

# ========== SAFETY CHECKS ==========
# Prevent multiple runs
if [ -f "$LOCK_FILE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Another remediation is running" | tee -a "$LOG_FILE"
    exit 1
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# ========== LOGGING ==========
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

# ========== WSL2 NETWORK FUNCTIONS ==========
get_wsl_host_ip() {
    # Get Windows host IP (acts as gateway in WSL2)
    grep nameserver /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -1
}

get_primary_interface() {
    ip route | grep default | awk '{print $5}' | head -1 || echo "eth0"
}

check_gateway() {
    local gateway="${1:-$(get_wsl_host_ip)}"

    if [ -z "$gateway" ]; then
        log "ERROR" "No gateway/host IP found"
        return 2
    fi

    log "INFO" "📡 Testing gateway: $gateway"

    if ping -c 2 -W 2 "$gateway" &>/dev/null; then
        log "INFO" "✅ Gateway reachable"
        return 0
    else
        log "ERROR" "❌ Gateway unreachable"
        return 1
    fi
}

check_internet() {
    log "INFO" "🌐 Testing internet connectivity..."

    # Test 1: DNS
    if nslookup google.com &>/dev/null 2>&1; then
        log "INFO" "✅ DNS working"
    else
        log "ERROR" "❌ DNS failed"
        return 1
    fi

    # Test 2: External IP
    if ping -c 2 -W 3 8.8.8.8 &>/dev/null; then
        log "INFO" "✅ External connectivity OK"
        return 0
    else
        log "ERROR" "❌ No internet access"
        return 2
    fi
}

# ========== SAFE REMEDIATION ACTIONS ==========
renew_dhcp_safe() {
    log "ACTION" "🔄 Attempting DHCP renewal..."

    # Method 1: dhclient if available
    if command -v dhclient &>/dev/null; then
        log "ACTION" "🔧 Using dhclient..."
        sudo dhclient -r 2>&1 | grep -v "Can't" | tee -a "$LOG_FILE"
        sleep 2
        sudo dhclient 2>&1 | grep -v "Can't" | tee -a "$LOG_FILE"
        sleep 3
        return 0
    fi

    # Method 2: Release/Renew IP manually
    local interface=$(get_primary_interface)
    if [ -n "$interface" ]; then
        log "ACTION" "🔧 Releasing IP on $interface..."
        sudo ip addr flush dev "$interface" 2>&1 | tee -a "$LOG_FILE"
        sudo ip link set "$interface" down 2>&1 | tee -a "$LOG_FILE"
        sleep 2
        sudo ip link set "$interface" up 2>&1 | tee -a "$LOG_FILE"
        sleep 3
        log "ACTION" "✅ IP released/renewed on $interface"
        return 0
    fi

    log "WARN" "⚠️ No DHCP method available"
    return 1
}

restart_interface_safe() {
    local interface=$(get_primary_interface)

    if [ -z "$interface" ]; then
        log "ERROR" "❌ No interface found"
        return 1
    fi

    log "ACTION" "🔄 Restarting interface: $interface"

    # Save current state
    local original_mtu=$(cat "/sys/class/net/$interface/mtu" 2>/dev/null || echo "1500")

    # Restart
    sudo ip link set "$interface" down 2>&1 | tee -a "$LOG_FILE"
    sleep 2
    sudo ip link set "$interface" up 2>&1 | tee -a "$LOG_FILE"

    # Restore MTU
    sudo ip link set "$interface" mtu "$original_mtu" 2>&1 | tee -a "$LOG_FILE"

    log "ACTION" "✅ Interface $interface restarted"
    sleep 3
    return 0
}

fix_dns_safe() {
    log "ACTION" "🔧 Configuring DNS..."

    # Backup original
    if [ -f /etc/resolv.conf ]; then
        sudo cp /etc/resolv.conf "/etc/resolv.conf.backup.$(date +%s)"
    fi

    # Set reliable DNS
    cat << EOF | sudo tee /etc/resolv.conf >/dev/null 2>&1
# Auto-remediated by NOC
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 9.9.9.9
options timeout:2 attempts:2
EOF

    # Make it sticky (WSL2 tends to overwrite)
    sudo chmod 644 /etc/resolv.conf 2>/dev/null || true

    log "ACTION" "✅ DNS set to Google + Cloudflare + Quad9"
    return 0
}

# ========== MAIN REMEDIATION FLOW ==========
run_remediation() {
    log "INFO" "🛡️ === AUTO-REMEDIATION STARTED ==="

    # Step 1: Pre-check
    log "INFO" "📋 Pre-check: Current network state"
    ip -br addr show | tee -a "$LOG_FILE"

    # Step 2: Check if remediation is needed
    if check_gateway && check_internet; then
        log "INFO" "✅ Network healthy - no remediation needed"
        return 0
    fi

    log "WARN" "🚨 Network issues detected - starting remediation"

    # Step 3: Remediation sequence
    local steps=(
        "renew_dhcp_safe"
        "restart_interface_safe"
        "fix_dns_safe"
    )

    local success=false

    for step in "${steps[@]}"; do
        log "INFO" "⚙️ Executing: $step"

        if $step; then
            log "INFO" "✅ $step completed"
            sleep 5  # Wait for network stabilization

            # Verify after each step
            if check_gateway && check_internet; then
                log "INFO" "🎉 Remediation SUCCESSFUL at step: $step"
                success=true
                break
            fi
        else
            log "ERROR" "❌ $step failed"
        fi
    done

    # Step 4: Final verification
    if $success; then
        log "INFO" "✅ NETWORK RESTORED SUCCESSFULLY"

        # Show new state
        log "INFO" "📋 Post-remediation state:"
        ip -br addr show | tee -a "$LOG_FILE"
        return 0
    else
        log "ERROR" "❌ ALL REMEDIATION STEPS FAILED"
        log "INFO" "🛠️ Manual intervention required"
        return 1
    fi
}

# ========== EXECUTION ==========
log "INFO" "=============================="
log "INFO" "🛠️ NOC AUTO-REMEDIATION v1.0"
log "INFO" "WSL2 Ubuntu - $(date)"
log "INFO" "=============================="

# Run remediation
if run_remediation; then
    log "INFO" "========== 🟢 REMEDIATION: SUCCESS =========="
else
    log "ERROR" "========== 🔴 REMEDIATION: FAILED =========="
fi

# Cleanup old logs (keep 7 days)
find "$LOG_DIR" -name "remediation-*.log" -mtime +7 -delete 2>/dev/null

log "INFO" "📂 Log saved: $LOG_FILE"
log "INFO" "=============================="
