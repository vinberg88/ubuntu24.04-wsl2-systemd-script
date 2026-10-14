# Ubuntu 24.04 & 26.04 WSL2 Systemd and Desktop Helper

This repository helps prepare **Ubuntu 24.04 and Ubuntu 26.04 on WSL2** for Linux desktop launchers that depend on systemd. It is intended to be used together with the desktop guides and launch scripts in [vinberg88/ubuntu](https://github.com/vinberg88/ubuntu/), where you can find instructions for Budgie and other desktop environments.

> [!IMPORTANT]
> Current WSL versions support systemd natively, and this is the default setup used by this script. The old **PID-namespace workaround** remains available only through the explicit `--legacy` option. The installer refuses to layer the workaround on top of native systemd.

<p align="center">
  <a href="https://github.com/vinberg88/ubuntu/">
    <img width="1037" height="271" alt="Ubuntu 24.04 WSL desktop banner" src="https://github.com/user-attachments/assets/8f6ec452-287a-400b-84b2-d73a2a012faf" />
  </a>
</p>

## What this repository does

- Detects and configures native systemd on Ubuntu 24.04 and Ubuntu 26.04.
- Provides a `--check` command for systemd, D-Bus, WSLg, X11, Wayland, audio, and OpenGL diagnostics.
- Keeps the original systemd namespace helper for older WSL installations.
- Provides the systemd foundation used by desktop launchers in the companion [Ubuntu desktop repository](https://github.com/vinberg88/ubuntu/).

This repository does **not** install a desktop environment or a Windows display server by itself. Follow the instructions for your chosen desktop in the companion repository after systemd is working.

## Requirements

- Windows 10 version 21H2 (build 19044) or newer, or Windows 11, for WSLg GUI application support.
- WSL2 with Ubuntu 24.04 or Ubuntu 26.04.
- A Linux user with `sudo` access.
- Internet access for package installation.

Check the distribution and WSL version from PowerShell:

```powershell
wsl --update
wsl --version
wsl --list --verbose
```

Make sure your Ubuntu 24.04 or Ubuntu 26.04 distribution is listed as WSL version `2`.

## Quick start

Run the script inside Ubuntu. Its default mode is safe for modern WSL: it uses native systemd and makes no legacy namespace changes when systemd is already active.

```bash
git clone https://github.com/vinberg88/ubuntu24.04-wsl2-systemd-script.git
cd ubuntu24.04-wsl2-systemd-script
bash ubuntu-wsl2-systemd-script.sh
```

If native systemd was not active, the script adds or updates the `[boot]` section in `/etc/wsl.conf` while preserving the other sections. Restart WSL from PowerShell when instructed:

```powershell
wsl --shutdown
```

After reopening Ubuntu, run the built-in diagnostics:

```bash
bash ubuntu-wsl2-systemd-script.sh --check
```

## Recommended setup: native WSL systemd

Recent WSL releases support systemd directly. The current Ubuntu installed by `wsl --install` normally uses systemd by default, so check before changing anything:

```bash
ps -p 1 -o comm=
systemctl status
```

If the first command prints `systemd`, native systemd is already active. **Skip the legacy script** and continue with the desktop instructions in [vinberg88/ubuntu](https://github.com/vinberg88/ubuntu/).

If systemd is not active, first make sure WSL is up to date. Then edit `/etc/wsl.conf` inside Ubuntu:

```bash
sudo nano /etc/wsl.conf
```

Add or merge the following section without removing any other settings you need:

```ini
[boot]
systemd=true
```

Save the file, close Ubuntu, and restart WSL from PowerShell:

```powershell
wsl --shutdown
```

Open Ubuntu again and verify:

```bash
ps -p 1 -o comm=
systemctl is-system-running
```

For more information, see Microsoft's guide: [Use systemd to manage Linux services with WSL](https://learn.microsoft.com/windows/wsl/systemd).

## Legacy setup: systemd namespace workaround

Use this section only when native WSL systemd is unavailable and updating WSL is not possible. The default command never installs this workaround.

The legacy script starts systemd inside a separate PID namespace and automatically enters that namespace when Bash starts. This was useful before Microsoft added native systemd support to WSL, but it is no longer the preferred configuration.

### Important changes made by the script

The script:

- installs `daemonize`, `dbus-user-session`, and `fontconfig`;
- copies `start-systemd-namespace` and `enter-systemd-namespace` to `/usr/sbin`;
- adds `/etc/sudoers.d/systemd-namespace`;
- loads the namespace helper from `/etc/bash.bashrc`;
- sets the Windows `WSLENV` and `BASH_ENV` variables when Windows interoperability is available; and
- removes several systemd user sockets and `systemd-binfmt` links to support the old namespace approach.

Review the scripts before running them. There is no automatic uninstall script, and the workaround should not be layered on top of native systemd.

### Install and run

Inside an older WSL installation:

```bash
sudo apt update
sudo apt install -y git util-linux-extra

git clone https://github.com/vinberg88/ubuntu24.04-wsl2-systemd-script.git
cd ubuntu24.04-wsl2-systemd-script
bash ubuntu-wsl2-systemd-script.sh --legacy
```

Enter your password when requested and wait for the script to finish. Then close Ubuntu and restart WSL from PowerShell:

```powershell
wsl --shutdown
```

Open Ubuntu again and test the namespace environment:

```bash
systemctl status
```

If the script reports that the workaround is already installed, do not use `--force` unless you intentionally want to reinstall the legacy files. Both `--legacy` and `--force` refuse to run when native systemd already owns PID 1.

## Start a desktop

Once systemd is working, choose a desktop and follow its installation and launch instructions in:

### [Ubuntu 24.04 desktops for WSL](https://github.com/vinberg88/ubuntu/)

The companion repository contains the desktop-specific packages, launch commands, and display configuration. Different desktop environments have different requirements, so use the guide for the desktop you actually installed.

WSLg is designed primarily for individual Linux GUI applications rather than a complete Linux desktop session. Full desktop environments may require additional launcher and display configuration. See [Run Linux GUI apps with WSL](https://learn.microsoft.com/windows/wsl/tutorials/gui-apps) for the officially supported WSLg workflow.

<p align="center">
  <a href="https://github.com/vinberg88/ubuntu/">
    <img width="810" height="403" alt="Ubuntu desktop start script" src="https://github.com/user-attachments/assets/f8cb0834-e40b-4a18-aa64-b3a98151e925" />
  </a>
</p>

## Troubleshooting

### `systemd` is not PID 1

Confirm that the distribution is using WSL2, update WSL, check `/etc/wsl.conf`, and run `wsl --shutdown` from PowerShell before reopening Ubuntu.

### `System has not been booted with systemd as init system`

You are not in a working systemd environment. Prefer the native WSL setup above. If you must use the legacy workaround, confirm that the installation completed and that you opened a new Bash session after restarting WSL.

### A GUI application opens, but the full desktop does not

That normally points to a desktop launcher, display, or session configuration issue rather than systemd alone. Follow the desktop-specific guide and inspect these variables inside Ubuntu:

```bash
printf 'DISPLAY=%s\nWAYLAND_DISPLAY=%s\nXDG_SESSION_TYPE=%s\n' \
  "$DISPLAY" "$WAYLAND_DISPLAY" "$XDG_SESSION_TYPE"
```

You can also run the complete non-destructive check:

```bash
bash ubuntu-wsl2-systemd-script.sh --check
```

### OpenGL reports `llvmpipe`

`llvmpipe` is software rendering and can make a full desktop slow. On a system with a supported GPU, test the WSL D3D12 renderer with:

```bash
GALLIUM_DRIVER=d3d12 glxinfo -B
```

Hybrid-GPU laptops may also need `MESA_D3D12_DEFAULT_ADAPTER_NAME` in the desktop launcher. Use a short adapter match such as `NVIDIA`, `AMD`, or `Intel` only after confirming the installed Windows graphics adapter. Do not hard-code one vendor for every computer.

### The script asks for manual Windows commands

If Windows interoperability is unavailable, the legacy script prints two `setx` commands. Run exactly those commands in Windows Command Prompt, then restart WSL with `wsl --shutdown`.

## Included files

| File | Purpose |
| --- | --- |
| `ubuntu-wsl2-systemd-script.sh` | Configures native WSL systemd, runs diagnostics, or installs legacy mode when explicitly requested. |
| `start-systemd-namespace` | Starts or enters the legacy namespace, but exits harmlessly when native systemd owns PID 1. |
| `enter-systemd-namespace` | Launches legacy systemd in a separate namespace with a startup timeout. |

<p align="center">
  <a href="https://github.com/vinberg88/ubuntu/">
    <img width="600" height="100" alt="Ubuntu 24.04 for WSL" src="https://github.com/user-attachments/assets/9ae95696-b2b9-49e8-a7ec-1d2e5e13eefb" />
  </a>
</p>

## Desktop example: Budgie

Budgie is one of the desktop environments available through the companion Ubuntu repository.

<p align="center">
  <a href="https://github.com/vinberg88/ubuntu/">
    <img width="1920" height="1080" alt="Ubuntu 24.04 Budgie Desktop running through WSL" src="https://github.com/user-attachments/assets/033ad70c-eb64-496c-9957-37466923a06d" />
  </a>
</p>

<p align="center">
  <a href="https://github.com/vinberg88">
    <img width="483" height="227" alt="Linux desktop artwork" src="https://github.com/user-attachments/assets/2410de82-e419-41b6-a7f0-9fc2db9d8b9d" />
  </a>
</p>

Have fun exploring Ubuntu 24.04 and Ubuntu 26.04 desktops on WSL2!
