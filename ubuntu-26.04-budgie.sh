#!/usr/bin/env bash

# Launch Ubuntu Budgie 10.10 as a nested Wayland desktop on WSLg.
#
# Ubuntu 26.04 uses Labwc for its Budgie Wayland session. Its wlroots 0.19.2
# nested Wayland backend can crash after a pointer-leave event, so the outer
# Labwc window uses WSLg's X11 transport while Budgie remains on Wayland.
# PrivateTmp=yes and a private X0 link give Labwc and Xwayland separate sockets
# without changing WSLg's global read-only mount.

set -Eeuo pipefail

readonly PROGRAM_NAME="$(basename "$0")"
readonly UNIT_NAME="budgie26-wsl.service"
readonly REQUIRED_COMMANDS=(systemctl systemd-run startbudgielabwc labwc Xwayland dbus-run-session wlr-randr)

CURRENT_USER="$(id -un)"
CURRENT_UID="$(id -u)"
CURRENT_GID="$(id -g)"
CURRENT_HOME="${HOME:-$(getent passwd "$CURRENT_UID" | cut -d: -f6)}"
RUNTIME_DIR="/run/user/${CURRENT_UID}"
CONFIG_DIR="$CURRENT_HOME/.config/budgie26-wsl"
SIZE_FILE="$CONFIG_DIR/size"
WINDOW_STATE_FILE="$CONFIG_DIR/window-state"

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
  start [SIZE]  Start Ubuntu Budgie, optionally at the requested size
  stop       Stop the Budgie session started by this script
  restart [SIZE] Restart the managed Budgie session
  size [SIZE] Change and remember the window size
  maximize   Maximize the WSLg window to the Windows work area
  restore    Restore the WSLg window to its remembered normal size
  status     Show whether the managed session is running
  doctor     Check Ubuntu, WSLg, systemd, and Budgie requirements
  log        Show the latest launcher and desktop log messages
  help       Show this help

This launcher is for Ubuntu 26.04 on WSL2. It uses WSLg, not X410.

Sizes may be written as 1600x900 or as a preset: small, medium, large,
or fullhd. Running '$PROGRAM_NAME size' without a size shows the current mode.
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

managed_wayland_display() {
    local cgroup pid process_name display_name

    cgroup="$(systemctl show "$UNIT_NAME" --property=ControlGroup --value 2>/dev/null || true)"
    [[ -n "$cgroup" && -r "/sys/fs/cgroup${cgroup}/cgroup.procs" ]] || return 1

    while IFS= read -r pid; do
        [[ -r "/proc/$pid/comm" && -r "/proc/$pid/environ" ]] || continue
        IFS= read -r process_name <"/proc/$pid/comm" || continue
        [[ "$process_name" == "budgie-panel" ]] || continue

        display_name="$(tr '\0' '\n' <"/proc/$pid/environ" | sed -n 's/^WAYLAND_DISPLAY=//p' | head -n 1)"
        if [[ -n "$display_name" && -S "$RUNTIME_DIR/$display_name" ]]; then
            printf '%s\n' "$display_name"
            return 0
        fi
    done <"/sys/fs/cgroup${cgroup}/cgroup.procs"

    return 1
}

send_windows_window_command() {
    local action="$1"
    local quiet="${2:-no}"
    local system_command powershell_source encoded_source

    case "$action" in
        maximize)
            system_command="0xF030"
            ;;
        restore)
            system_command="0xF120"
            ;;
        *)
            die "Unsupported Windows window command: $action"
            ;;
    esac

    command -v powershell.exe >/dev/null 2>&1 ||
        die "Windows interoperability is required for '$action'."
    command -v iconv >/dev/null 2>&1 || die "The iconv command is required."
    command -v base64 >/dev/null 2>&1 || die "The base64 command is required."

    powershell_source="$(cat <<'POWERSHELL'
Add-Type @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public static class Budgie26WindowControl {
    private const uint WmSysCommand = 0x0112;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(
        IntPtr window,
        uint message,
        IntPtr command,
        IntPtr parameter
    );

    [DllImport("user32.dll")]
    private static extern bool IsZoomed(IntPtr window);

    private static Process FindWindow() {
        Process newest = null;
        foreach (Process process in Process.GetProcessesByName("msrdc")) {
            string title = process.MainWindowTitle;
            bool isLabwcWindow =
                title.StartsWith("labwc - ", StringComparison.Ordinal) ||
                title.StartsWith("wlroots - ", StringComparison.Ordinal);
            if (process.MainWindowHandle == IntPtr.Zero || !isLabwcWindow) {
                continue;
            }

            if (newest == null || process.StartTime > newest.StartTime) {
                newest = process;
            }
        }
        return newest;
    }

    public static bool Run(int command) {
        Process process = null;
        for (int attempt = 0; attempt < 40; attempt++) {
            process = FindWindow();
            if (process != null) {
                break;
            }
            Thread.Sleep(250);
        }

        if (process == null) {
            return false;
        }

        bool expectedMaximized = command == 0xF030;
        if (IsZoomed(process.MainWindowHandle) == expectedMaximized) {
            return true;
        }

        if (!PostMessage(
                process.MainWindowHandle,
                WmSysCommand,
                new IntPtr(command),
                IntPtr.Zero)) {
            return false;
        }

        for (int attempt = 0; attempt < 20; attempt++) {
            Thread.Sleep(100);
            if (IsZoomed(process.MainWindowHandle) == expectedMaximized) {
                return true;
            }
        }
        return false;
    }
}
'@

if ([Budgie26WindowControl]::Run(__SYSTEM_COMMAND__)) {
    exit 0
}
exit 1
POWERSHELL
)"
    powershell_source="${powershell_source/__SYSTEM_COMMAND__/$system_command}"
    encoded_source="$(printf '%s' "$powershell_source" | iconv -f UTF-8 -t UTF-16LE | base64 -w 0)"

    if ! powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand "$encoded_source" \
        >/dev/null 2>&1; then
        if [[ "$quiet" == "yes" ]]; then
            return 1
        fi
        die "WSLg did not accept the Windows '$action' command."
    fi
}

maximize_session() {
    local quiet="${1:-no}"

    require_supported_system
    unit_is_active || die "Ubuntu Budgie is not running. Start it before maximizing the window."
    send_windows_window_command maximize "$quiet"
    mkdir -p "$CONFIG_DIR"
    printf 'maximized\n' >"$WINDOW_STATE_FILE"
    if [[ "$quiet" != "yes" ]]; then
        say "Ubuntu Budgie is maximized to the Windows work area."
    fi
}

restore_session_window() {
    local quiet="${1:-no}"

    require_supported_system
    unit_is_active || die "Ubuntu Budgie is not running. Start it before restoring the window."
    send_windows_window_command restore "$quiet"
    mkdir -p "$CONFIG_DIR"
    printf 'restored\n' >"$WINDOW_STATE_FILE"
    if [[ "$quiet" != "yes" ]]; then
        say "Ubuntu Budgie is restored to its normal window size."
    fi
}

normalize_size() {
    local requested="${1,,}"
    local width height

    case "$requested" in
        small)
            requested="1280x720"
            ;;
        medium)
            requested="1440x810"
            ;;
        large)
            requested="1600x900"
            ;;
        fullhd)
            requested="1920x1080"
            ;;
    esac

    if [[ ! "$requested" =~ ^([0-9]{3,4})x([0-9]{3,4})$ ]]; then
        die "Invalid size '$1'. Use WIDTHxHEIGHT, for example 1600x900."
    fi

    width="${BASH_REMATCH[1]}"
    height="${BASH_REMATCH[2]}"
    if (( width < 640 || width > 7680 || height < 480 || height > 4320 )); then
        die "Size $requested is outside the supported range 640x480 to 7680x4320."
    fi

    printf '%sx%s\n' "$width" "$height"
}

show_size() {
    local nested_display

    require_supported_system
    command -v wlr-randr >/dev/null 2>&1 ||
        die "wlr-randr is missing. Install it with: sudo apt install wlr-randr"
    unit_is_active || die "Ubuntu Budgie is not running. Start it before checking the size."
    nested_display="$(managed_wayland_display)" || die "Could not find the managed Budgie Wayland display."

    env XDG_RUNTIME_DIR="$RUNTIME_DIR" WAYLAND_DISPLAY="$nested_display" wlr-randr
    if [[ -r "$SIZE_FILE" ]]; then
        printf 'Remembered size: %s\n' "$(<"$SIZE_FILE")"
    fi
}

set_size() {
    local requested_size="$1"
    local normalized_size nested_display output_name

    require_supported_system
    command -v wlr-randr >/dev/null 2>&1 ||
        die "wlr-randr is missing. Install it with: sudo apt install wlr-randr"
    unit_is_active || die "Ubuntu Budgie is not running. Start it before changing the size."

    normalized_size="$(normalize_size "$requested_size")"
    if command -v powershell.exe >/dev/null 2>&1; then
        if send_windows_window_command restore yes; then
            sleep 0.5
        else
            warn "Could not restore the Windows window before resizing; continuing."
        fi
    fi
    nested_display="$(managed_wayland_display)" || die "Could not find the managed Budgie Wayland display."
    output_name="$(env XDG_RUNTIME_DIR="$RUNTIME_DIR" WAYLAND_DISPLAY="$nested_display" \
        wlr-randr | awk 'NR == 1 { print $1 }')"
    [[ -n "$output_name" ]] || die "Could not find the Budgie output name."

    env XDG_RUNTIME_DIR="$RUNTIME_DIR" WAYLAND_DISPLAY="$nested_display" \
        wlr-randr --output "$output_name" --custom-mode "$normalized_size"

    mkdir -p "$CONFIG_DIR"
    printf '%s\n' "$normalized_size" >"$SIZE_FILE"
    printf 'restored\n' >"$WINDOW_STATE_FILE"
    say "Budgie window size: $normalized_size (remembered for the next start)"
}

apply_start_size() {
    local requested_size="${1:-}"
    local remembered_window_state=""

    if [[ -z "$requested_size" && -r "$WINDOW_STATE_FILE" ]]; then
        remembered_window_state="$(<"$WINDOW_STATE_FILE")"
    fi

    if [[ -n "$requested_size" ]]; then
        set_size "$requested_size"
    elif [[ "$remembered_window_state" == "maximized" ]]; then
        maximize_session yes
    elif [[ -r "$SIZE_FILE" ]]; then
        set_size "$(<"$SIZE_FILE")"
    fi
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
        printf '  sudo apt update && sudo apt install ubuntu-budgie-desktop labwc xwayland dbus-daemon wlr-randr\n' >&2
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
    local requested_size="${1:-}"
    local wayland_display
    local -a run_command

    if [[ -n "$requested_size" ]]; then
        normalize_size "$requested_size" >/dev/null
    fi
    require_supported_system
    require_commands

    if unit_is_active; then
        if [[ -n "$requested_size" ]]; then
            set_size "$requested_size"
        else
            say "Ubuntu Budgie is already running."
            say "Use '$PROGRAM_NAME status' for details."
        fi
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
        --setenv="DISPLAY=${DISPLAY:-:0}"
        --setenv="WAYLAND_DISPLAY=$wayland_display"
        --setenv="XDG_SESSION_TYPE=wayland"
        --setenv="WLR_BACKENDS=x11"
        --setenv="WLR_RENDERER=pixman"
        --setenv="GDK_BACKEND=wayland,x11"
        --setenv="QT_QPA_PLATFORM=wayland"
        --setenv="SDL_VIDEODRIVER=wayland"
    )

    if [[ -S /mnt/wslg/PulseServer ]]; then
        run_command+=(--setenv="PULSE_SERVER=unix:/mnt/wslg/PulseServer")
    fi

    run_command+=(
        /usr/bin/bash
        -c
        'install -d -m 1777 /tmp/.X11-unix &&
            ln -sfn /mnt/wslg/.X11-unix/X0 /tmp/.X11-unix/X0 &&
            exec /usr/bin/startbudgielabwc'
    )
    "${run_command[@]}"

    for _ in {1..80}; do
        if unit_is_active &&
            unit_has_process labwc &&
            unit_has_process Xwayland &&
            unit_has_process budgie-panel; then
            say "Ubuntu Budgie is running in a WSLg window."
            apply_start_size "$requested_size"
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
    local requested_size="${1:-}"

    if unit_is_active; then
        stop_session
    fi
    start_session "$requested_size"
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

    if command -v powershell.exe >/dev/null 2>&1 &&
        command -v iconv >/dev/null 2>&1 &&
        command -v base64 >/dev/null 2>&1; then
        say "[OK] Windows maximize and restore controls are available"
    else
        say "[WARN] Windows maximize and restore controls are unavailable"
        say "       Starting, stopping, and resizing the desktop will still work."
        ((warnings += 1))
    fi

    if command -v dpkg-query >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1; then
        local desktop_view_version
        desktop_view_version="$(dpkg-query -W -f='${Version}' budgie-desktop-view 2>/dev/null || true)"
        if [[ -n "$desktop_view_version" ]] &&
            dpkg --compare-versions "$desktop_view_version" lt 10.10.3; then
            printf '[INFO] Budgie Desktop View %s sorts desktop icons automatically\n' "$desktop_view_version"
            say "[INFO] Free desktop-icon placement requires version 10.10.3 or newer"
        fi
    fi

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
            start_session "${2:-}"
            ;;
        stop)
            stop_session
            ;;
        restart)
            restart_session "${2:-}"
            ;;
        size|resize)
            if [[ -n "${2:-}" ]]; then
                set_size "$2"
            else
                show_size
            fi
            ;;
        maximize|max)
            maximize_session
            ;;
        restore|windowed)
            restore_session_window
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
