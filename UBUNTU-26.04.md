
<img width="1072" height="466" alt="Ubuntubanner" src="https://github.com/user-attachments/assets/27a67c2f-1f42-46c2-a5d3-81a3c79dae4f" />

# Ubuntu 26.04 on WSL2

This page contains the Ubuntu 26.04-specific instructions for this repository. The same script also supports Ubuntu 24.04, but keeping the version notes separate makes installation and troubleshooting easier to follow.

## Tested configuration

The current script has been tested with:

- Ubuntu 26.04.1 LTS
- WSL2 kernel `6.18.54.1-microsoft-standard-WSL2`
- native systemd as PID 1
- system and user systemd services
- user D-Bus
- WSLg X11, Wayland, and audio sockets
- Mesa OpenGL diagnostics

Ubuntu 26.04 should use **native WSL systemd**. The legacy PID-namespace workaround is retained for old WSL installations, but it should not be installed when systemd already owns PID 1.

## 1. Check WSL from Windows

Open PowerShell and run:

```powershell
wsl --update
wsl --version
wsl --list --verbose
```

Confirm that `Ubuntu-26.04` is using WSL version `2`.

## 2. Download or update the project

For a new installation, run inside Ubuntu 26.04:

```bash
git clone https://github.com/vinberg88/ubuntu24.04-wsl2-systemd-script.git
cd ubuntu24.04-wsl2-systemd-script
```

If the project is already installed:

```bash
cd ~/ubuntu24.04-wsl2-systemd-script
git pull --ff-only
```

## 3. Configure native systemd

Run the main script without legacy options:

```bash
bash ubuntu-wsl2-systemd-script.sh
```

If systemd is already active, the script leaves the native setup in place. If it updates `/etc/wsl.conf`, close Ubuntu and restart WSL from PowerShell:

```powershell
wsl --shutdown
```

Then open Ubuntu 26.04 again.

## 4. Verify the installation

Run:

```bash
bash ubuntu-wsl2-systemd-script.sh --check
```

A healthy Ubuntu 26.04 installation should report:

- `PID 1: systemd`
- `System systemd: running`
- `User systemd: running`
- `User D-Bus: available`
- available X11, Wayland, and WSLg audio sockets

The command is diagnostic and does not change the system.

## OpenGL and GPU acceleration

Install the optional Mesa diagnostic tools if `glxinfo` is missing:

```bash
sudo apt update
sudo apt install mesa-utils
```

Run the check again:

```bash
bash ubuntu-wsl2-systemd-script.sh --check
```

If the renderer contains `llvmpipe`, OpenGL is using the CPU rather than the GPU. Test WSL's D3D12 Mesa driver with:

```bash
GALLIUM_DRIVER=d3d12 glxinfo -B
```

On a computer with more than one GPU, an explicit adapter selection may be useful:

```bash
MESA_D3D12_DEFAULT_ADAPTER_NAME=AMD GALLIUM_DRIVER=d3d12 glxinfo -B
MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA GALLIUM_DRIVER=d3d12 glxinfo -B
MESA_D3D12_DEFAULT_ADAPTER_NAME=Intel GALLIUM_DRIVER=d3d12 glxinfo -B
```

Use only the adapter name that matches the Windows computer. Do not copy a vendor-specific setting permanently until it has been tested.

## Important: do not use legacy mode with native systemd

Do not run the following command on a normal Ubuntu 26.04 installation:

```bash
bash ubuntu-wsl2-systemd-script.sh --legacy
```

The script refuses to install the legacy workaround when native systemd is active. Legacy mode exists only for old WSL versions where native systemd cannot be enabled.

## Desktop environments

This repository prepares systemd and checks the WSL graphical environment. It does not install a complete desktop by itself.

After the diagnostic check succeeds, continue with the desktop-specific launchers and instructions in [vinberg88/ubuntu](https://github.com/vinberg88/ubuntu/).

Full desktop sessions are more demanding than individual WSLg applications. When a desktop opens but feels slow, first check whether OpenGL is using `llvmpipe`, and then verify the launcher's display and D3D12 adapter settings.

## Troubleshooting

### `$'\r': command not found`

This means the local shell script has Windows CRLF line endings or is an older checkout. Update the repository first:

```bash
git pull --ff-only
```

The repository includes `.gitattributes` rules that keep shell scripts in Unix LF format. Verify the current file if needed:

```bash
file ubuntu-wsl2-systemd-script.sh
```

### Systemd is not PID 1

Run the main script once, restart WSL with `wsl --shutdown`, reopen Ubuntu, and run `--check` again. Also confirm that the distribution is using WSL2 rather than WSL1.

### X11 or Wayland socket is unavailable

Update WSL from PowerShell and restart it. The diagnostic checks expect a current WSLg installation for graphical Linux applications.

---

Return to the [main README](README.md).
