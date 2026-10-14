#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODE="native"
FORCE_LEGACY=0

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTION]

Prepare Ubuntu on WSL for systemd-based desktop launchers.

Options:
  --check          Show systemd, WSLg, display, and graphics status.
  --native         Use native WSL systemd (default and recommended).
  --legacy         Install the old PID-namespace workaround.
  --force          Reinstall legacy files. Implies --legacy.
  -h, --help       Show this help text.

Native systemd is supported by modern WSL and is the correct mode for
Ubuntu 24.04 and Ubuntu 26.04. Legacy mode is only for old WSL versions
that cannot provide native systemd.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'Warning: %s\n' "$*" >&2
}

is_wsl() {
    [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null
}

pid1_command() {
    ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]'
}

native_systemd_running() {
    [ "$(pid1_command)" = "systemd" ]
}

read_os_release() {
    OS_ID="unknown"
    OS_VERSION="unknown"
    OS_PRETTY="Unknown Linux"

    if [ -r /etc/os-release ]; then
        # The file is supplied by the installed distribution.
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_PRETTY="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
    fi
}

print_socket_state() {
    local label="$1"
    local path="$2"

    if [ -S "$path" ]; then
        printf '%s: available\n' "$label"
    else
        printf '%s: unavailable\n' "$label"
    fi
}

show_status() {
    local system_state="not running"
    local user_state="not available"
    local renderer="not tested (install mesa-utils for glxinfo)"
    local d3d12_renderer=""

    read_os_release

    if native_systemd_running; then
        system_state="$(systemctl is-system-running 2>/dev/null || true)"
        [ -n "$system_state" ] || system_state="running"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        user_state="$(systemctl --user is-system-running 2>/dev/null || true)"
        [ -n "$user_state" ] || user_state="not available"
    fi

    if command -v glxinfo >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
        renderer="$(glxinfo -B 2>/dev/null | sed -n 's/^OpenGL renderer string: //p' | head -n 1)"
        [ -n "$renderer" ] || renderer="unavailable"
    fi

    printf 'Operating system: %s\n' "$OS_PRETTY"
    printf 'WSL distribution: %s\n' "${WSL_DISTRO_NAME:-unknown}"
    printf 'Kernel: %s\n' "$(uname -r)"
    printf 'PID 1: %s\n' "$(pid1_command)"
    printf 'System systemd: %s\n' "$system_state"
    printf 'User systemd: %s\n' "$user_state"
    printf 'DISPLAY: %s\n' "${DISPLAY:-not set}"
    printf 'WAYLAND_DISPLAY: %s\n' "${WAYLAND_DISPLAY:-not set}"

    print_socket_state "User D-Bus" "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"
    print_socket_state "X11 socket" "/tmp/.X11-unix/X0"
    print_socket_state "Wayland socket" "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/${WAYLAND_DISPLAY:-wayland-0}"
    print_socket_state "WSLg audio" "/mnt/wslg/PulseServer"

    printf 'OpenGL renderer: %s\n' "$renderer"

    if [ "$renderer" != "unavailable" ] && printf '%s' "$renderer" | grep -qi llvmpipe; then
        warn "OpenGL is using software rendering. A desktop launcher may need an explicit D3D12 adapter selection."
        d3d12_renderer="$(GALLIUM_DRIVER=d3d12 glxinfo -B 2>/dev/null | sed -n 's/^OpenGL renderer string: //p' | head -n 1)"
        if [ -n "$d3d12_renderer" ] && ! printf '%s' "$d3d12_renderer" | grep -qi llvmpipe; then
            printf 'Available D3D12 renderer: %s\n' "$d3d12_renderer"
        fi
    fi
}

validate_supported_ubuntu() {
    read_os_release

    [ "$OS_ID" = "ubuntu" ] || warn "This script is designed for Ubuntu; detected $OS_PRETTY."

    case "$OS_VERSION" in
        24.04|26.04)
            ;;
        *)
            warn "Ubuntu $OS_VERSION is not one of the tested releases (24.04 and 26.04)."
            ;;
    esac
}

write_native_wsl_conf() {
    local source_file="/dev/null"
    local temporary_file

    temporary_file="$(mktemp)"

    if [ -f /etc/wsl.conf ]; then
        source_file="/etc/wsl.conf"
    fi

    awk '
        BEGIN {
            in_boot = 0
            boot_seen = 0
            systemd_seen = 0
        }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            if (in_boot && !systemd_seen) {
                print "systemd=true"
            }
            in_boot = ($0 ~ /^[[:space:]]*\[boot\][[:space:]]*$/)
            if (in_boot) {
                boot_seen = 1
                systemd_seen = 0
            }
            print
            next
        }
        {
            if (in_boot && $0 ~ /^[[:space:]]*systemd[[:space:]]*=/) {
                if (!systemd_seen) {
                    print "systemd=true"
                    systemd_seen = 1
                }
                next
            }
            print
        }
        END {
            if (in_boot && !systemd_seen) {
                print "systemd=true"
            }
            if (!boot_seen) {
                if (NR > 0) {
                    print ""
                }
                print "[boot]"
                print "systemd=true"
            }
        }
    ' "$source_file" > "$temporary_file"

    sudo install -o root -g root -m 0644 "$temporary_file" /etc/wsl.conf
    rm -f "$temporary_file"
}

configure_native_systemd() {
    validate_supported_ubuntu

    if native_systemd_running; then
        printf 'Native WSL systemd is already active. No installation changes are needed.\n'
        show_status
        return 0
    fi

    is_wsl || die "This does not appear to be a WSL distribution."

    write_native_wsl_conf

    printf 'Native systemd has been enabled in /etc/wsl.conf.\n'
    printf 'Close this Ubuntu window and run the following command in Windows PowerShell:\n\n'
    printf '  wsl --shutdown\n\n'
    printf 'Open Ubuntu again, then run:\n\n'
    printf '  bash %s --check\n' "$SCRIPT_NAME"
}

interop_mount_root() {
    local mount_root="/mnt/"
    local configured_root

    if [ -f /etc/wsl.conf ]; then
        configured_root="$(awk -F '=' '/^[[:space:]]*root[[:space:]]*=/ {print $2; exit}' /etc/wsl.conf | xargs)"
        [ -z "$configured_root" ] || mount_root="$configured_root"
    fi

    printf '%s' "$mount_root"
}

windows_cmd() {
    local candidate
    local mount_root

    if command -v cmd.exe >/dev/null 2>&1; then
        command -v cmd.exe
        return 0
    fi

    mount_root="$(interop_mount_root)"
    for candidate in "${mount_root}"*/Windows/System32/cmd.exe; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

install_legacy_workaround() {
    local cmd_path=""

    validate_supported_ubuntu
    is_wsl || [ "$FORCE_LEGACY" -eq 1 ] || die "Legacy mode can only be installed inside WSL."

    if native_systemd_running; then
        die "Native systemd is already running as PID 1. Refusing to install the legacy namespace workaround."
    fi

    if [ -f /usr/sbin/start-systemd-namespace ] && [ "$FORCE_LEGACY" -ne 1 ]; then
        die "The legacy workaround is already installed. Use --force only if you intentionally need to reinstall it."
    fi

    [ -f "$SCRIPT_DIR/start-systemd-namespace" ] || die "Missing $SCRIPT_DIR/start-systemd-namespace"
    [ -f "$SCRIPT_DIR/enter-systemd-namespace" ] || die "Missing $SCRIPT_DIR/enter-systemd-namespace"

    sudo hwclock -s 2>/dev/null || warn "Could not set the WSL clock with hwclock; continuing."
    sudo apt-get update
    sudo apt-get install -y daemonize dbus-user-session fontconfig util-linux-extra

    sudo install -o root -g root -m 0644 "$SCRIPT_DIR/start-systemd-namespace" /usr/sbin/start-systemd-namespace
    sudo install -o root -g root -m 0755 "$SCRIPT_DIR/enter-systemd-namespace" /usr/sbin/enter-systemd-namespace

    sudo tee /etc/sudoers.d/systemd-namespace >/dev/null <<'EOF'
Defaults        env_keep += WSLPATH
Defaults        env_keep += WSLENV
Defaults        env_keep += WSL_INTEROP
Defaults        env_keep += WSL_DISTRO_NAME
Defaults        env_keep += PRE_NAMESPACE_PATH
Defaults        env_keep += PRE_NAMESPACE_PWD
%sudo ALL=(ALL) NOPASSWD: /usr/sbin/enter-systemd-namespace
EOF
    sudo chmod 0440 /etc/sudoers.d/systemd-namespace

    if command -v visudo >/dev/null 2>&1; then
        sudo visudo -cf /etc/sudoers.d/systemd-namespace >/dev/null
    fi

    if ! grep -q 'start-systemd-namespace' /etc/bash.bashrc; then
        sudo sed -i '2a# Start or enter the legacy systemd PID namespace in WSL2\nsource /usr/sbin/start-systemd-namespace' /etc/bash.bashrc
    fi

    sudo rm -f /etc/systemd/user/sockets.target.wants/dirmngr.socket
    sudo rm -f /etc/systemd/user/sockets.target.wants/gpg-agent*.socket
    sudo rm -f /lib/systemd/system/sysinit.target.wants/proc-sys-fs-binfmt_misc.automount
    sudo rm -f /lib/systemd/system/sysinit.target.wants/proc-sys-fs-binfmt_misc.mount
    sudo rm -f /lib/systemd/system/sysinit.target.wants/systemd-binfmt.service

    if cmd_path="$(windows_cmd)"; then
        "$cmd_path" /C setx WSLENV BASH_ENV/u
        "$cmd_path" /C setx BASH_ENV /etc/bash.bashrc
    else
        warn "Windows interoperability is unavailable. Run these commands in Windows Command Prompt:"
        printf '  setx WSLENV BASH_ENV/u\n'
        printf '  setx BASH_ENV /etc/bash.bashrc\n'
    fi

    printf 'The legacy systemd namespace workaround has been installed.\n'
    printf 'Restart WSL from PowerShell with: wsl --shutdown\n'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --check)
            MODE="check"
            ;;
        --native)
            MODE="native"
            ;;
        --legacy)
            MODE="legacy"
            ;;
        --force)
            MODE="legacy"
            FORCE_LEGACY=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            die "Unknown option: $1"
            ;;
    esac
    shift
done

case "$MODE" in
    check)
        validate_supported_ubuntu
        show_status
        native_systemd_running
        ;;
    native)
        configure_native_systemd
        ;;
    legacy)
        install_legacy_workaround
        ;;
esac

