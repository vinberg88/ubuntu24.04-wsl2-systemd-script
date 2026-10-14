#!/usr/bin/env bash

# Launch Ubuntu Budgie 10.10 as a nested Wayland desktop on WSLg.
#
# Ubuntu 26.04 uses Labwc for its Budgie Wayland session. WSLg exposes its
# X11 socket directory as a read-only mount without the sticky bit expected by
# wlroots/Xwayland. Running the desktop in a transient systemd service with
# PrivateTmp=yes gives Xwayland a correct private socket directory without
# changing WSLg's global mount.

set -Eeuo pipefail

readonly PROGRAM_NAME="$(basename "$0")"
readonly UNIT_NAME="budgie26-wsl.service"
readonly REQUIRED_COMMANDS=(systemctl systemd-run startbudgielabwc labwc Xwayland dbus-run-session)

CURRENT_USER="$(id -un)"
CURRENT_UID="$(id -u)"
CURRENT_GID="$(id -g)"
CURRENT_HOME="${HOME:-$(getent passwd "$CURRENT_UID" | cut -d: -f6)}"
RUNTIME_DIR="/run/user/${CURRENT_UID}"

say() {
    printf '%s\n' "$*"
}

warn() {
    printf 'Warning: %s\n' "$*" >&2
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $PROGRAM_NAME COMMAND

Commands:
  start      Start Ubuntu Budgie in a WSLg window
  stop       Stop the Budgie session started by this script
  restart    Restart the managed Budgie session
  status     Show whether the managed session is running
  doctor     Check Ubuntu, WSLg, systemd, and Budgie requirements
  log        Show the latest launcher and desktop log messages
  help       Show this help

This launcher is for Ubuntu 26.04 on WSL2. It uses WSLg, not X410.
EOF
}

os_value() {
    local key="$1"
    [[ -r /etc/os-release ]] || return 1
    . /etc/os-release
    printf '%s\n' "${!key:-}"
}

is_wsl2() {
    grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null &&
        grep -qiE 'wsl2|microsoft-standard' /proc/sys/kernel/osrelease 2>/dev/null
}

is_ubuntu_2604() {
    [[ "$(os_value ID 2>/dev/null || true)" == "ubuntu" ]] &&
        [[ "$(os_value VERSION_ID 2>/dev/null || true)" == "26.04" ]]
}

find_wayland_display() {
    local candidate name

    if [[ -n "${WAYLAND_DISPLAY:-}" && -S "$RUNTIME_DIR/$WAYLAND_DISPLAY" ]]; then
        printf '%s\n' "$WAYLAND_DISPLAY"
        return 0
    fi

    for candidate in "$RUNTIME_DIR"/wayland-*; do
        [[ -S "$candidate" ]] || continue
        name="$(basename "$candidate")"
        [[ "$name" == *.lock ]] && continue
        printf '%s\n' "$name"
        return 0
    done

    return 1
}

unit_is_active() {
    systemctl is-active --quiet "$UNIT_NAME"
}

unit_has_process() {
    local expected_name="$1"
    local cgroup pid process_name

    cgroup="$(systemctl show "$UNIT_NAME" --property=ControlGroup --value 2>/dev/null || true)"
    [[ -n "$cgroup" && -r "/sys/fs/cgroup${cgroup}/cgroup.procs" ]] || return 1

    while IFS= read -r pid; do
        [[ -r "/proc/$pid/comm" ]] || continue
        IFS= read -r process_name <"/proc/$pid/comm" || continue
        [[ "$process_name" == "$expected_name" ]] && return 0
    done <"/sys/fs/cgroup${cgroup}/cgroup.procs"

    return 1
}

require_supported_system() {
    (( CURRENT_UID != 0 )) || die "Run this command as your normal Linux user, not as root."
    is_wsl2 || die "This launcher requires WSL2."
    is_ubuntu_2604 || die "This launcher is intended for Ubuntu 26.04."
    [[ "$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]')" == "systemd" ]] ||
        die "Native WSL systemd must be running as PID 1."
    [[ -d "$RUNTIME_DIR" ]] || die "User runtime directory $RUNTIME_DIR is missing."
}

require_commands() {
    local command_name
    local -a missing=()

    for command_name in "${REQUIRED_COMMANDS[@]}"; do
        command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
    done

    if (( ${#missing[@]} > 0 )); then
        printf 'Error: missing required commands: %s\n' "${missing[*]}" >&2
        printf 'Install the Budgie Wayland session first, for example:\n' >&2
        printf '  sudo apt update && sudo apt install ubuntu-budgie-desktop labwc xwayland dbus-daemon\n' >&2
        exit 1
    fi
}

prepare_budgie_config() {
    local config_dir="$CURRENT_HOME/.config/budgie-desktop/labwc"

    mkdir -p "$config_dir"

    # Ubuntu 26.04 currently ships startbudgielabwc without the source file it
    # tries to copy. An empty user environment file is valid and avoids that
    # non-fatal packaging error.
    if [[ ! -e "$config_dir/environment" && ! -e /usr/share/budgie-desktop/labwc/environment ]]; then
        : >"$config_dir/environment"
    fi
}

start_session() {
    local wayland_display
    local -a run_command

    require_supported_system
    require_commands

    if unit_is_active; then
        say "Ubuntu Budgie is already running."
        say "Use '$PROGRAM_NAME status' for details."
        return 0
    fi

    wayland_display="$(find_wayland_display)" ||
        die "No WSLg Wayland socket was found in $RUNTIME_DIR. Update WSL, run 'wsl --shutdown' in PowerShell, and try again."

    prepare_budgie_config

    say "Starting Ubuntu Budgie 26.04 through WSLg..."
    sudo -v

    run_command=(
        sudo systemd-run
        --unit="$UNIT_NAME"
        --collect
        --description="Ubuntu Budgie 26.04 desktop on WSLg"
        --uid="$CURRENT_USER"
        --gid="$CURRENT_GID"
        --property="WorkingDirectory=$CURRENT_HOME"
        --property="PrivateTmp=yes"
        --property="KillMode=mixed"
        --property="TimeoutStopSec=15s"
        --property="Restart=no"
        --setenv="HOME=$CURRENT_HOME"
        --setenv="USER=$CURRENT_USER"
        --setenv="LOGNAME=$CURRENT_USER"
        --setenv="XDG_RUNTIME_DIR=$RUNTIME_DIR"
        --setenv="WAYLAND_DISPLAY=$wayland_display"
        --setenv="XDG_SESSION_TYPE=wayland"
        --setenv="WLR_BACKENDS=wayland"
        --setenv="WLR_RENDERER=pixman"
        --setenv="GDK_BACKEND=wayland,x11"
        --setenv="QT_QPA_PLATFORM=wayland"
        --setenv="SDL_VIDEODRIVER=wayland"
    )

    if [[ -S /mnt/wslg/PulseServer ]]; then
        run_command+=(--setenv="PULSE_SERVER=unix:/mnt/wslg/PulseServer")
    fi

    run_command+=(/usr/bin/startbudgielabwc)
    "${run_command[@]}"

    for _ in {1..80}; do
        if unit_is_active &&
            unit_has_process labwc &&
            unit_has_process Xwayland &&
            unit_has_process budgie-panel; then
            say "Ubuntu Budgie is running in a WSLg window."
            say "Logs: $PROGRAM_NAME log"
            return 0
        fi

        if systemctl is-failed --quiet "$UNIT_NAME"; then
            break
        fi

        sleep 0.25
    done

    warn "Budgie did not stay active. The latest log follows."
    sudo journalctl -u "$UNIT_NAME" -n 80 --no-pager || true
    return 1
}

stop_session() {
    require_supported_system

    if ! systemctl list-units --all --full --no-legend "$UNIT_NAME" | grep -q "$UNIT_NAME"; then
        say "Ubuntu Budgie is not running."
        return 0
    fi

    say "Stopping Ubuntu Budgie..."
    sudo systemctl stop "$UNIT_NAME"
    say "Ubuntu Budgie has stopped."
}

restart_session() {
    if unit_is_active; then
        stop_session
    fi
    start_session
}

show_status() {
    if unit_is_active; then
        say "Ubuntu Budgie is running."
        systemctl status "$UNIT_NAME" --no-pager
    else
        say "Ubuntu Budgie is not running."
        systemctl status "$UNIT_NAME" --no-pager 2>/dev/null || true
    fi
}

show_log() {
    sudo journalctl -u "$UNIT_NAME" -n 120 --no-pager
}

doctor_check() {
    local failures=0
    local warnings=0
    local command_name wayland_display os_pretty mount_options socket_mode

    os_pretty="$(os_value PRETTY_NAME 2>/dev/null || printf 'unknown')"
    printf 'Operating system: %s\n' "$os_pretty"
    printf 'Kernel: %s\n' "$(uname -r)"
    printf 'User: %s (uid %s)\n' "$CURRENT_USER" "$CURRENT_UID"

    if is_wsl2; then
        say "[OK] WSL2 detected"
    else
        say "[FAIL] WSL2 was not detected"
        ((failures += 1))
    fi

    if is_ubuntu_2604; then
        say "[OK] Ubuntu 26.04 detected"
    else
        say "[FAIL] This launcher supports Ubuntu 26.04"
        ((failures += 1))
    fi

    if [[ "$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]')" == "systemd" ]]; then
        say "[OK] Native systemd is PID 1"
    else
        say "[FAIL] Native systemd is not PID 1"
        ((failures += 1))
    fi

    if wayland_display="$(find_wayland_display 2>/dev/null)"; then
        printf '[OK] WSLg Wayland socket: %s/%s\n' "$RUNTIME_DIR" "$wayland_display"
    else
        say "[FAIL] No WSLg Wayland socket found"
        ((failures += 1))
    fi

    if [[ -e /tmp/.X11-unix ]]; then
        socket_mode="$(stat -c '%a' /tmp/.X11-unix 2>/dev/null || printf '?')"
        mount_options="$(findmnt -n -o OPTIONS -T /tmp/.X11-unix 2>/dev/null | head -n 1 || true)"
        printf '[INFO] WSLg X11 socket directory mode: %s; mount options: %s\n' "$socket_mode" "${mount_options:-unknown}"
        if [[ "$socket_mode" != "1777" ]]; then
            say "[OK] The launcher will isolate Xwayland with PrivateTmp=yes"
        fi
    fi

    for command_name in "${REQUIRED_COMMANDS[@]}"; do
        if command -v "$command_name" >/dev/null 2>&1; then
            printf '[OK] %s: %s\n' "$command_name" "$(command -v "$command_name")"
        else
            printf '[FAIL] Missing command: %s\n' "$command_name"
            ((failures += 1))
        fi
    done

    if [[ ! -e /usr/share/budgie-desktop/labwc/environment ]]; then
        say "[INFO] Ubuntu's optional Labwc environment template is missing"
        say "[OK] The launcher supplies a safe per-user replacement"
    fi

    if pgrep -u "$CURRENT_UID" -x budgie-panel >/dev/null 2>&1 && ! unit_is_active; then
        say "[WARN] An unmanaged Budgie session is already present"
        say "       Close that old session before judging the managed desktop."
        ((warnings += 1))
    fi

    say "[INFO] Budgie 10.10 uses Labwc/wlroots and is launched through WSLg."
    say "[INFO] X410 is not used by this Ubuntu 26.04 launcher."

    if (( failures == 0 )); then
        printf 'Result: ready (%s warning(s))\n' "$warnings"
        return 0
    fi

    printf 'Result: not ready (%s failure(s), %s warning(s))\n' "$failures" "$warnings"
    return 1
}

main() {
    case "${1:-help}" in
        start)
            start_session
            ;;
        stop)
            stop_session
            ;;
        restart)
            restart_session
            ;;
        status)
            show_status
            ;;
        doctor|check)
            doctor_check
            ;;
        log|logs)
            show_log
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
}

main "$@"
