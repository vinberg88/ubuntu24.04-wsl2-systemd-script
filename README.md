# Ubuntu 24.04 WSL2 Systemd Helper for WSL Desktops

Start any desktop via this script for Ubuntu 24.04 - Desktop example for Ubuntu 24.04 - BUDGIE DESKTOP - 2026

<p align="center">
<a href="https://github.com/vinberg88/ubuntu/">
<img width="1920" height="1080" alt="Ubuntu 24.04 Budgie Desktop" src="https://github.com/user-attachments/assets/033ad70c-eb64-496c-9957-37466923a06d" />
</p>

This project prepares **Ubuntu 24.04 on WSL2** for complete X11 desktop
sessions displayed through **X410**. The same systemd helper is used by GNOME,
UKUI, Pantheon, Budgie, and other Ubuntu desktop environments.

This repository installs the shared systemd compatibility layer. It does **not**
install one particular desktop. Choose a desktop guide below for its packages,
environment settings, and launch command.

> [!IMPORTANT] 

THSI IS BETA AND WE ARE WORKING ON VERSION FOR UBUNTU 26.04.

> Ubuntu 26.04 uses a separate WSLg-based project. See
> [`ubuntu26.04-wsl2-budgie`](https://github.com/vinberg88/ubuntu26.04-wsl2-budgie)
> when working with Ubuntu 26.04.


<p align="center">
<a href="https://github.com/vinberg88/ubuntu26.04-wsl2-budgie">
<img width="594" height="354" alt="Ubuntu-26 04-BETA" src="https://github.com/user-attachments/assets/a7a0af99-db0d-4b09-9342-3d77cd4a58c5" />
</p>

## Ubuntu 24.04 desktop guides

| Desktop | Complete installation guide | Launch command used by the guide |
| --- | --- | --- |
| GNOME | [Ubuntu 24.04 GNOME](https://github.com/vinberg88/ubuntu/blob/main/UBUNTU-24.04-GNOME.txt) | `dbus-launch gnome-session` |
| UKUI | [Ubuntu 24.04 UKUI](https://github.com/vinberg88/ubuntu/blob/main/UBUNTU-24.04-UKUI.txt) | `dbus-launch ukui-x410` |
| Pantheon | [Ubuntu 24.04 Pantheon](https://github.com/vinberg88/ubuntu/blob/main/Ubuntu-24.04-Pantheon.txt) | `io.elementary.wingpanel & plank & gala` |
| Budgie | [Ubuntu 24.04 Budgie](https://github.com/vinberg88/ubuntu/blob/main/Ubuntu24.04-BUDGIE.txt) | `budgie-desktop` |

Follow the complete guide for the desktop you want. The launch commands above
are only a quick reference; they depend on the packages and X410 environment
configured in each guide.

## What the helper does

The default **Classic desktop mode**:

- installs the original systemd PID-namespace helpers;
- installs the shared `daemonize`, D-Bus, font, and namespace dependencies;
- adds the namespace entry hook to Bash;
- sets `systemd=false` in `/etc/wsl.conf` for this compatibility mode; and
- prevents native and Classic systemd user managers from competing for D-Bus
  and `/run/user/<uid>`.

The helper also carries the shell environment into the namespace. Set
`DISPLAY` and the X11 session variables exactly as described by your selected
desktop guide before launching that desktop.

## Install the shared helper

First confirm in Windows PowerShell that Ubuntu 24.04 is running as WSL 2:

```powershell
wsl --update
wsl --list --verbose
```

Install the desktop packages from one of the guides above. Then run this inside
Ubuntu 24.04:

```bash
sudo apt update
sudo apt install -y git mesa-utils daemonize util-linux-extra
git clone https://github.com/vinberg88/ubuntu24.04-wsl2-systemd-script.git
cd ubuntu24.04-wsl2-systemd-script
bash ubuntu-wsl2-systemd-script.sh --classic-desktop
```

The option can be omitted because Classic desktop mode is the default:

```bash
bash ubuntu-wsl2-systemd-script.sh
```

If the repository is already installed, update it instead of cloning it again:

```bash
cd ~/ubuntu24.04-wsl2-systemd-script
git pull --ff-only
bash ubuntu-wsl2-systemd-script.sh --classic-desktop
```

Close all Ubuntu windows and restart WSL from Windows PowerShell:

```powershell
wsl --shutdown
```

## Verify and start a desktop

1. Start X410 in Windows.
2. Open Ubuntu 24.04.
3. Apply the `DISPLAY` and X11 environment commands from your desktop guide.
4. Run the check:

```bash
cd ~/ubuntu24.04-wsl2-systemd-script
bash ubuntu-wsl2-systemd-script.sh --check
printf 'DISPLAY=%s\n' "$DISPLAY"
```

A healthy Classic installation reports:

```text
/etc/wsl.conf systemd: false
Classic Bash hook: installed
[OK] Classic desktop systemd namespace is active without native systemd.
Result: ready (0 warning(s))
```

Now use the launch command from the selected desktop guide. Keep the Ubuntu
terminal open while the desktop session is running.

## Commands

| Command | Purpose |
| --- | --- |
| `bash ubuntu-wsl2-systemd-script.sh` | Install Classic desktop mode |
| `bash ubuntu-wsl2-systemd-script.sh --classic-desktop` | Explicitly install Classic desktop mode |
| `bash ubuntu-wsl2-systemd-script.sh --check` | Diagnose systemd, D-Bus, display, and mode conflicts |
| `bash ubuntu-wsl2-systemd-script.sh --native` | Remove Classic mode and enable native WSL systemd |
| `bash ubuntu-wsl2-systemd-script.sh --help` | Show all options |

The old `--classic-budgie` and `--legacy` options remain as compatibility
aliases. They install the same desktop-neutral Classic mode.

## Classic mode and native WSL systemd

Do not run both modes together. Complete X410 desktop sessions documented in
the guides use Classic mode. Native mode is available when you want to remove
the compatibility layer and return to Microsoft's native WSL systemd:

```bash
cd ~/ubuntu24.04-wsl2-systemd-script
bash ubuntu-wsl2-systemd-script.sh --native
```

Then close Ubuntu and run `wsl --shutdown` from Windows PowerShell.

## Troubleshooting

### A desktop does not start

Run:

```bash
bash ubuntu-wsl2-systemd-script.sh --check
```

If native and Classic systemd are running together, reinstall Classic mode and
restart WSL:

```bash
bash ubuntu-wsl2-systemd-script.sh --classic-desktop
```

Then run `wsl --shutdown` from Windows PowerShell.

### `Cannot open display` or an empty `DISPLAY`

Start X410 first, reopen Ubuntu, and repeat the `DISPLAY` command from your
selected desktop guide. Check it with:

```bash
printf 'DISPLAY=%s\n' "$DISPLAY"
```

Different WSL and X410 configurations can use different display addresses, so
follow the working value produced by your guide and computer.

### `Transport endpoint is not connected`

Two systemd user managers may have competed for `/run/user/<uid>`. Reinstall
Classic mode, shut down WSL completely, and reopen Ubuntu.

### `$'\r': command not found`

Update the checkout with `git pull --ff-only`. This repository's
`.gitattributes` keeps shell scripts in Unix LF format.

## Origin and included files - Starta Amazing desktops for WSL =)

<p align="center">
<a href="https://github.com/vinberg88/ubuntu">
<img width="1021" height="717" alt="desktops for Ubuntu" src="https://github.com/user-attachments/assets/83685ed4-a1aa-417e-9b2a-d62b17f42624" />
</p>

| File | Purpose |
| --- | --- |
| `ubuntu-wsl2-systemd-script.sh` | Installs, removes, and diagnoses Classic or native systemd |
| `start-systemd-namespace` | Starts or enters the Classic systemd namespace |
| `enter-systemd-namespace` | Creates and enters the Classic PID namespace |
| `CREDITS.md` | Original project attribution |
| `UBUNTU-26.04.md` | Redirect to the separate Ubuntu 26.04 repository |
| `ubuntu-26.04-budgie.sh` | Compatibility copy only; use the Ubuntu 26.04 repository |

<p align="center">
  <a href="https://github.com/vinberg88/ubuntu/">
 <img width="573" height="258" alt="ubuntu" src="https://github.com/user-attachments/assets/101e5e10-b099-4792-b995-037a2cd81c1c" />
</p>

Kind Regards,
Mattias Vinberg - Stockholm - Sweden - 2026

