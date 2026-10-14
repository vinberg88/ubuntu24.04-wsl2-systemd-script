#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CLASSIC_START_HELPER="$SCRIPT_DIR/start-systemd-namespace"
readonly CLASSIC_ENTER_HELPER="$SCRIPT_DIR/enter-systemd-namespace"

MODE="classic"

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTION]

Configure systemd for Ubuntu 24.04 on WSL2.

Options:
  --classic-budgie  Install the proven PID-namespace mode for Budgie (default)
  --legacy          Alias for --classic-budgie
  --native          Remove Classic mode and enable native WSL systemd
  --check           Diagnose the current systemd, D-Bus, and display setup
  --force           Reinstall Classic Budgie mode
  -h, --help        Show this help text

Classic Budgie mode is based on the original DamionGans WSL2 systemd helper.
It disables native WSL systemd before using its own namespace, preventing two
systemd instances from competing for the user D-Bus and runtime sockets.

Ubuntu 26.04 users should use:
https://github.com/vinberg88/ubuntu26.04-wsl2-budgie
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'Warning: %s\n' "$*" >&2
}

run_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

is_wsl() {
    [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null
}

read_os_release() {
    OS_ID="unknown"
    OS_VERSION="unknown"
    OS_PRETTY="Unknown Linux"

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_PRETTY="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
    fi
}

require_ubuntu_2404() {
    read_os_release
    is_wsl || die "This script must be run inside WSL2."
    [[ "$OS_ID" == "ubuntu" ]] || die "This script requires Ubuntu; detected $OS_PRETTY."
    [[ "$OS_VERSION" == "24.04" ]] || die "This repository requires Ubuntu 24.04; detected $OS_PRETTY."
}

pid1_arguments() {
    tr '\0' ' ' </proc/1/cmdline 2>/dev/null | sed 's/[[:space:]]*$//'
}

classic_pid1_running() {
    pid1_arguments | grep -qE '^/lib/systemd/systemd (--unit|--system-unit)=basic\.target$'
}

native_pid1_running() {
    [[ "$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]')" == "systemd" ]] &&
        ! classic_pid1_running
}

classic_process_count() {
    ps -eo args= 2>/dev/null |
        awk '/^\/lib\/systemd\/systemd (--unit|--system-unit)=basic\.target$/ { count++ } END { print count + 0 }'
}

classic_hook_installed() {
    grep -Eq '^[[:space:]]*(source|\.)[[:space:]]+/usr/sbin/start-systemd-namespace([[:space:]]|$)' /etc/bash.bashrc 2>/dev/null
}

wsl_systemd_setting() {
    if [[ ! -r /etc/wsl.conf ]]; then
        printf 'not set\n'
        return
    fi

    awk '
        /^[[:space:]]*\[boot\][[:space:]]*$/ { in_boot = 1; next }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ { in_boot = 0 }
        in_boot && /^[[:space:]]*systemd[[:space:]]*=/ {
            split($0, parts, "=")
            value = parts[2]
            gsub(/[[:space:]]/, "", value)
            print tolower(value)
            found = 1
            exit
        }
        END { if (!found) print "not set" }
    ' /etc/wsl.conf
}

render_wsl_conf() {
    local value="$1"
    local source_file="$2"

    awk -v value="$value" '
        BEGIN { in_boot = 0; boot_seen = 0; setting_seen = 0 }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            if (in_boot && !setting_seen) print "systemd=" value
            in_boot = ($0 ~ /^[[:space:]]*\[boot\][[:space:]]*$/)
            if (in_boot) { boot_seen = 1; setting_seen = 0 }
            print
            next
        }
        {
            if (in_boot && $0 ~ /^[[:space:]]*systemd[[:space:]]*=/) {
                if (!setting_seen) { print "systemd=" value; setting_seen = 1 }
                next
            }
            print
        }
        END {
            if (in_boot && !setting_seen) print "systemd=" value
            if (!boot_seen) {
                if (NR > 0) print ""
                print "[boot]"
                print "systemd=" value
            }
        }
    ' "$source_file"
}

write_wsl_systemd_setting() {
    local value="$1"
    local source_file="/dev/null"
    local temporary_file

    [[ -f /etc/wsl.conf ]] && source_file="/etc/wsl.conf"
    temporary_file="$(mktemp)"
    render_wsl_conf "$value" "$source_file" >"$temporary_file"
    run_root install -o root -g root -m 0644 "$temporary_file" /etc/wsl.conf
    rm -f "$temporary_file"
}

interop_mount_root() {
    local configured_root=""

    if [[ -r /etc/wsl.conf ]]; then
        configured_root="$(awk -F= '/^[[:space:]]*root[[:space:]]*=/ { print $2; exit }' /etc/wsl.conf | xargs)"
    fi

    printf '%s\n' "${configured_root:-/mnt/}"
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
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

install_classic_hook() {
    if classic_hook_installed; then
        return
    fi

    printf '\n# Start or enter the Classic Budgie systemd namespace in WSL2\nsource /usr/sbin/start-systemd-namespace\n' |
        run_root tee -a /etc/bash.bashrc >/dev/null
}

remove_classic_hook() {
    local temporary_file

    [[ -f /etc/bash.bashrc ]] || return
    temporary_file="$(mktemp)"

    awk '
        /Classic Budgie systemd namespace in WSL2/ { next }
        /Start or enter (the legacy )?systemd PID namespace in WSL2/ { next }
        /^[[:space:]]*(source|\.)[[:space:]]+\/usr\/sbin\/start-systemd-namespace([[:space:]]|$)/ { next }
        { print }
    ' /etc/bash.bashrc >"$temporary_file"

    run_root install -o root -g root -m 0644 "$temporary_file" /etc/bash.bashrc
    rm -f "$temporary_file"
}

install_classic_budgie() {
    local cmd_path=""

    require_ubuntu_2404
    [[ -f "$CLASSIC_START_HELPER" ]] || die "Missing $CLASSIC_START_HELPER"
    [[ -f "$CLASSIC_ENTER_HELPER" ]] || die "Missing $CLASSIC_ENTER_HELPER"

    printf 'Installing Classic Budgie systemd support for Ubuntu 24.04...\n'
    run_root hwclock -s 2>/dev/null || warn "Could not update the WSL clock with hwclock; continuing."
    run_root apt-get update
    run_root apt-get install -y daemonize dbus-user-session fontconfig util-linux-extra

    run_root install -o root -g root -m 0644 "$CLASSIC_START_HELPER" /usr/sbin/start-systemd-namespace
    run_root install -o root -g root -m 0755 "$CLASSIC_ENTER_HELPER" /usr/sbin/enter-systemd-namespace

    run_root tee /etc/sudoers.d/systemd-namespace >/dev/null <<'EOF'
Defaults        env_keep += WSLPATH
Defaults        env_keep += WSLENV
Defaults        env_keep += WSL_INTEROP
Defaults        env_keep += WSL_DISTRO_NAME
Defaults        env_keep += PRE_NAMESPACE_PATH
Defaults        env_keep += PRE_NAMESPACE_PWD
%sudo ALL=(ALL) NOPASSWD: /usr/sbin/enter-systemd-namespace
EOF
    run_root chmod 0440 /etc/sudoers.d/systemd-namespace
    if command -v visudo >/dev/null 2>&1; then
        run_root visudo -cf /etc/sudoers.d/systemd-namespace >/dev/null
    fi

    install_classic_hook
    write_wsl_systemd_setting false

    run_root rm -f /etc/systemd/user/sockets.target.wants/dirmngr.socket
    run_root rm -f /etc/systemd/user/sockets.target.wants/gpg-agent*.socket
    run_root rm -f /lib/systemd/system/sysinit.target.wants/proc-sys-fs-binfmt_misc.automount
    run_root rm -f /lib/systemd/system/sysinit.target.wants/proc-sys-fs-binfmt_misc.mount
    run_root rm -f /lib/systemd/system/sysinit.target.wants/systemd-binfmt.service

    if cmd_path="$(windows_cmd)"; then
        "$cmd_path" /C setx WSLENV BASH_ENV/u >/dev/null
        "$cmd_path" /C setx BASH_ENV /etc/bash.bashrc >/dev/null
    else
        warn "Windows interoperability is unavailable; interactive Bash will still use the installed hook."
    fi

    printf '\nClassic Budgie mode is installed. Native systemd is disabled for this mode.\n'
    printf 'Close Ubuntu and run this command in Windows PowerShell:\n\n'
    printf '  wsl --shutdown\n\n'
    printf 'Open Ubuntu again, then verify with:\n\n'
    printf '  bash %s --check\n' "$SCRIPT_NAME"
}

configure_native_systemd() {
    require_ubuntu_2404
    remove_classic_hook
    run_root rm -f /etc/sudoers.d/systemd-namespace
    run_root rm -f /usr/sbin/start-systemd-namespace /usr/sbin/enter-systemd-namespace
    run_root systemctl preset systemd-binfmt.service proc-sys-fs-binfmt_misc.automount >/dev/null 2>&1 || true
    write_wsl_systemd_setting true

    printf 'Classic mode has been removed and native WSL systemd has been enabled.\n'
    printf 'Close Ubuntu and run "wsl --shutdown" in Windows PowerShell.\n'
}

show_status() {
    local classic_count
    local configured_mode
    local pid1_args
    local system_state="not running"
    local user_state="not available"
    local failures=0
    local warnings=0

    read_os_release
    classic_count="$(classic_process_count)"
    configured_mode="$(wsl_systemd_setting)"
    pid1_args="$(pid1_arguments)"

    if [[ "$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]')" == "systemd" ]]; then
        system_state="$(systemctl is-system-running 2>/dev/null || true)"
        [[ -n "$system_state" ]] || system_state="running"
        user_state="$(systemctl --user is-system-running 2>/dev/null || true)"
        [[ -n "$user_state" ]] || user_state="not available"
    fi

    printf 'Operating system: %s\n' "$OS_PRETTY"
    printf 'WSL distribution: %s\n' "${WSL_DISTRO_NAME:-unknown}"
    printf 'Kernel: %s\n' "$(uname -r)"
    printf 'PID 1: %s\n' "${pid1_args:-unknown}"
    printf '/etc/wsl.conf systemd: %s\n' "$configured_mode"
    printf 'Classic Bash hook: '
    if classic_hook_installed; then printf 'installed\n'; else printf 'not installed\n'; fi
    printf 'Classic systemd processes: %s\n' "$classic_count"
    printf 'System systemd: %s\n' "$system_state"
    printf 'User systemd: %s\n' "$user_state"
    printf 'User D-Bus: %s\n' "${DBUS_SESSION_BUS_ADDRESS:-not set}"
    printf 'DISPLAY: %s\n' "${DISPLAY:-not set}"
    printf 'WAYLAND_DISPLAY: %s\n' "${WAYLAND_DISPLAY:-not set}"

    if [[ "$configured_mode" == "true" && "$classic_count" -gt 0 ]]; then
        printf '[FAIL] Native and Classic systemd are running together.\n'
        printf '       Reinstall Classic mode and restart WSL to remove the conflict.\n'
        ((failures += 1))
    elif classic_pid1_running; then
        if [[ "$configured_mode" == "false" ]]; then
            printf '[OK] Classic Budgie systemd namespace is active without native systemd.\n'
        else
            printf '[WARN] Classic mode is active, but /etc/wsl.conf does not explicitly disable native systemd.\n'
            ((warnings += 1))
        fi
    elif native_pid1_running; then
        printf '[OK] Native WSL systemd is active.\n'
        if classic_hook_installed; then
            printf '[WARN] A Classic Bash hook is still installed and should be removed with --native.\n'
            ((warnings += 1))
        fi
    else
        printf '[FAIL] No working systemd environment was detected.\n'
        ((failures += 1))
    fi

    if [[ "$user_state" == "not available" || "$user_state" == "unknown" ]]; then
        printf '[FAIL] The user systemd manager is unavailable; Budgie may not start.\n'
        ((failures += 1))
    fi

    if ((failures == 0)); then
        printf 'Result: ready (%s warning(s))\n' "$warnings"
        return 0
    fi

    printf 'Result: not ready (%s failure(s), %s warning(s))\n' "$failures" "$warnings"
    return 1
}

main() {
    while (($# > 0)); do
        case "$1" in
            --classic-budgie|--legacy|--force)
                MODE="classic"
                ;;
            --native)
                MODE="native"
                ;;
            --check)
                MODE="check"
                ;;
            -h|--help)
                usage
                return 0
                ;;
            *)
                usage >&2
                die "Unknown option: $1"
                ;;
        esac
        shift
    done

    case "$MODE" in
        classic) install_classic_budgie ;;
        native) configure_native_systemd ;;
        check) show_status ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
