# Ubuntu 24.04 WSL2 Systemd Helper

Prepare **Ubuntu 24.04 on WSL2** for Linux desktop launchers that require
systemd.

> [!IMPORTANT]
> Are you using **Ubuntu 26.04**? Use the separate
> [`ubuntu26.04-wsl2-budgie`](https://github.com/vinberg88/ubuntu26.04-wsl2-budgie)
> repository instead. It contains the tested Ubuntu 26.04 Budgie installer and
> WSLg launcher.

<p align="center">
  <a href="https://github.com/vinberg88/ubuntu/">
    <img width="1037" height="271" alt="Ubuntu 24.04 WSL desktop banner" src="https://github.com/user-attachments/assets/8f6ec452-287a-400b-84b2-d73a2a012faf" />
  </a>
</p>

## Choose the correct repository

| Ubuntu version | Use this project |
| --- | --- |
| Ubuntu 24.04 LTS | This repository |
| Ubuntu 26.04 LTS | [`ubuntu26.04-wsl2-budgie`](https://github.com/vinberg88/ubuntu26.04-wsl2-budgie) |

## Quick start for Ubuntu 24.04

First update WSL from Windows PowerShell:

```powershell
wsl --update
wsl --list --verbose
```

Confirm that Ubuntu 24.04 is using WSL version `2`. Then open Ubuntu and run:

```bash
sudo apt update
sudo apt install -y git mesa-utils daemonize util-linux-extra
git clone https://github.com/vinberg88/ubuntu24.04-wsl2-systemd-script.git
cd ubuntu24.04-wsl2-systemd-script
bash ubuntu-wsl2-systemd-script.sh
```

Modern WSL uses **native systemd**. If the script changes `/etc/wsl.conf`, close
Ubuntu and run this once in Windows PowerShell:

```powershell
wsl --shutdown
```

Open Ubuntu again and check the installation:

```bash
cd ~/ubuntu24.04-wsl2-systemd-script
bash ubuntu-wsl2-systemd-script.sh --check
```

The check reports systemd, D-Bus, WSLg, X11, Wayland, audio, and OpenGL status.
It does not change the system.

## Start a desktop

This repository prepares systemd; it does not install a complete desktop by
itself. Desktop-specific packages and launch instructions are available here:

### [Ubuntu 24.04 desktops for WSL](https://github.com/vinberg88/ubuntu/)

## Native systemd and the old workaround

Native WSL systemd is the recommended setup. If this command prints `systemd`,
you already have the correct configuration:

```bash
ps -p 1 -o comm=
```

The files `start-systemd-namespace` and `enter-systemd-namespace` are the
project's original workaround from before WSL supported systemd natively. They
remain for historical compatibility only.

Use `--legacy` only when all of the following are true:

- native systemd is unavailable;
- WSL cannot be updated; and
- you understand that the workaround changes Bash startup, sudoers, and the
  systemd namespace.

Do not install legacy mode when systemd is already PID 1. The script refuses to
layer the workaround on top of native systemd.

## Useful commands

| Command | Purpose |
| --- | --- |
| `bash ubuntu-wsl2-systemd-script.sh` | Check or enable native WSL systemd |
| `bash ubuntu-wsl2-systemd-script.sh --check` | Show non-destructive diagnostics |
| `bash ubuntu-wsl2-systemd-script.sh --help` | Show all options |
| `bash ubuntu-wsl2-systemd-script.sh --legacy` | Install the historical workaround |

## Troubleshooting

### `systemd` is not PID 1

Update WSL, run the default script, close Ubuntu, and run `wsl --shutdown` from
PowerShell before reopening the distribution.

### `$'\r': command not found`

The script has Windows CRLF line endings or comes from an older checkout. Run:

```bash
git pull --ff-only
```

This repository includes `.gitattributes` rules that keep shell scripts in Unix
LF format.

### A GUI application opens but the desktop does not

That normally points to the desktop launcher or display configuration rather
than systemd. Run the diagnostic check, then follow the instructions for the
desktop you installed:

```bash
bash ubuntu-wsl2-systemd-script.sh --check
```

### OpenGL reports `llvmpipe`

`llvmpipe` is software rendering. Install the Mesa diagnostic tool and test
WSL's D3D12 renderer:

```bash
sudo apt install -y mesa-utils
GALLIUM_DRIVER=d3d12 glxinfo -B
```

Hybrid-GPU computers may need an adapter selection in their desktop launcher,
but do not permanently select NVIDIA, AMD, or Intel until you have confirmed
which Windows graphics adapter should be used.

## Included files

| File | Purpose |
| --- | --- |
| `ubuntu-wsl2-systemd-script.sh` | Native systemd setup, diagnostics, and explicit legacy mode |
| `start-systemd-namespace` | Historical namespace helper |
| `enter-systemd-namespace` | Historical namespace entry helper |
| `UBUNTU-26.04.md` | Redirect for old Ubuntu 26.04 links |
| `ubuntu-26.04-budgie.sh` | Compatibility copy; current development is in the Ubuntu 26.04 repository |

For Microsoft's supported configuration, see
[Use systemd to manage Linux services with WSL](https://learn.microsoft.com/windows/wsl/systemd).
