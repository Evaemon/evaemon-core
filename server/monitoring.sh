#!/bin/bash
set -eo pipefail

# Post-quantum sshd monitoring tool.
#
# Displays:
#   1. Service status (systemctl / process check fallback)
#   2. Active SSH connections on the configured port
#   3. Recent authentication events from the system journal / auth log
#   4. PQ algorithm negotiation events
#   5. Optional continuous watch mode (polls every N seconds)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../shared/config.sh"
source "${SCRIPT_DIR}/../shared/functions.sh"

# ── Monitoring sections ───────────────────────────────────────────────────────

show_service_status() {
    log_section "Service Status"

    if command -v systemctl &>/dev/null; then
        local status
        status="$(systemctl is-active "${SERVICE_NAME}.service" 2>/dev/null || echo "unknown")"
        log_info "  systemctl status: ${status}"

        if systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
            log_info "  Service is RUNNING"
            systemctl status "${SERVICE_NAME}.service" --no-pager -l 2>/dev/null | \
                while IFS= read -r line; do log_info "    ${line}"; done
        else
            log_warn "  Service is NOT running (${status})"
            log_warn "  Start with: systemctl start ${SERVICE_NAME}.service"
        fi
    else
        # No systemd — check via process
        local pid
        pid="$(_sshd_pid)"
        if [[ -n "$pid" ]]; then
            log_info "  sshd is running (PID ${pid})"
            ps -p "$pid" -o pid,user,%cpu,%mem,etime,args --no-headers 2>/dev/null | \
                while IFS= read -r line; do log_info "    ${line}"; done
        else
            log_warn "  sshd is NOT running"
        fi
    fi
}

show_active_connections() {
    log_section "Active SSH Connections"

    local port
    port="$(_configured_port)"

    if command -v ss &>/dev/null; then
        local conns
        conns="$(ss -tnp "sport = :${port}" 2>/dev/null | tail -n +2 || true)"
        if [[ -z "$conns" ]]; then
            log_info "  No active connections on port ${port}."
        else
            log_info "  Connections on port ${port}:"
            while IFS= read -r line; do
                log_info "    ${line}"
            done <<< "$conns"
        fi
    elif command -v netstat &>/dev/null; then
        local conns
        conns="$(netstat -tnp 2>/dev/null | grep ":${port} " || true)"
        if [[ -z "$conns" ]]; then
            log_info "  No active connections on port ${port}."
        else
            while IFS= read -r line; do log_info "    ${line}"; done <<< "$conns"
        fi
    else
        log_warn "  Neither ss nor netstat found -- cannot list connections."
    fi
}

show_auth_events() {
    local n="${1:-20}"
    log_section "Recent Authentication Events (last ${n} entries)"

    if command -v journalctl &>/dev/null; then
        journalctl -u "${SERVICE_NAME}.service" -n "${n}" --no-pager 2>/dev/null | \
            while IFS= read -r line; do log_info "  ${line}"; done || \
            log_warn "  No journal entries found for ${SERVICE_NAME}."
    elif [[ -f /var/log/auth.log ]]; then
        grep -i "sshd" /var/log/auth.log | tail -n "${n}" | \
            while IFS= read -r line; do log_info "  ${line}"; done
    elif [[ -f /var/log/secure ]]; then
        grep -i "sshd" /var/log/secure | tail -n "${n}" | \
            while IFS= read -r line; do log_info "  ${line}"; done
    else
        log_warn "  No accessible auth log found."
    fi
}

show_pq_algorithm_events() {
    local n="${1:-30}"
    log_section "Post-Quantum Algorithm Negotiation Events (last ${n} log lines searched)"

    local algo_pattern
    algo_pattern="$(IFS='|'; echo "${ALGORITHMS[*]}")"
    if [[ -z "$algo_pattern" ]]; then
        log_warn "  No algorithms configured -- skipping PQ event search."
        return
    fi

    local matches=""
    if command -v journalctl &>/dev/null; then
        matches="$(journalctl -u "${SERVICE_NAME}.service" -n "${n}" --no-pager 2>/dev/null \
                   | grep -E "${algo_pattern}" || true)"
    elif [[ -f /var/log/auth.log ]]; then
        matches="$(grep -E "${algo_pattern}" /var/log/auth.log 2>/dev/null | tail -n "${n}" || true)"
    elif [[ -f /var/log/secure ]]; then
        matches="$(grep -E "${algo_pattern}" /var/log/secure 2>/dev/null | tail -n "${n}" || true)"
    fi

    if [[ -z "$matches" ]]; then
        log_info "  No PQ algorithm negotiation events found in recent logs."
    else
        while IFS= read -r line; do log_info "  ${line}"; done <<< "$matches"
    fi
}

show_uptime_and_load() {
    log_section "System Load"
    local pid
    pid="$(_sshd_pid)"
    if [[ -n "$pid" ]]; then
        local elapsed
        elapsed="$(ps -p "$pid" -o etime --no-headers 2>/dev/null | tr -d ' ' || echo "unknown")"
        log_info "  sshd PID ${pid} uptime: ${elapsed}"
    fi

    if [[ -f /proc/loadavg ]]; then
        local load
        load="$(cat /proc/loadavg 2>/dev/null)"
        log_info "  System load averages: ${load}"
    elif command -v uptime &>/dev/null; then
        local load
        load="$(uptime 2>/dev/null)"
        log_info "  ${load}"
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

print_snapshot() {
    show_service_status
    show_active_connections
    show_auth_events        20
    show_pq_algorithm_events 30
    show_uptime_and_load
}

main() {
    log_section "Post-Quantum sshd Monitor"

    echo "Options:"
    echo "1. One-shot status snapshot"
    echo "2. Continuous watch (refresh every N seconds)"
    read -rp "Choice (1-2) [1]: " mode_choice
    mode_choice="${mode_choice:-1}"

    case "$mode_choice" in
        1)
            print_snapshot
            ;;
        2)
            read -rp "Refresh interval in seconds [10]: " interval
            interval="${interval:-10}"
            if [[ ! "$interval" =~ ^[1-9][0-9]*$ ]]; then
                log_fatal "Interval must be a positive integer."
            fi
            log_info "Watching (Ctrl-C to stop, refresh every ${interval}s) ..."
            while true; do
                clear
                print_snapshot
                log_info "Next refresh in ${interval}s — Ctrl-C to quit."
                sleep "${interval}"
            done
            ;;
        *)
            log_fatal "Invalid choice."
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
