
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

## Ubuntu Budgie 26.04 launcher

Ubuntu 26.04 uses the Wayland-based Budgie 10.10 session with Labwc. The included `ubuntu-26.04-budgie.sh` launcher runs that session as a managed systemd service inside a WSLg window. Budgie remains a Wayland desktop; the outer Labwc window uses WSLg's X11 transport to avoid an Ubuntu 26.04 wlroots 0.19.2 pointer-leave crash in its nested Wayland backend.

Install Ubuntu Budgie and the required Wayland components if they are not already installed:

```bash
sudo apt update
sudo apt install ubuntu-budgie-desktop labwc xwayland dbus-daemon wlr-randr
```

Check the environment without changing anything:

```bash
bash ubuntu-26.04-budgie.sh doctor
```

Start the desktop:

```bash
bash ubuntu-26.04-budgie.sh start
```

The first start asks for the normal Linux `sudo` password because the launcher creates a temporary systemd service. The desktop itself still runs as the current user.

For a shorter command, install the launcher locally once:

```bash
sudo install -m 0755 ubuntu-26.04-budgie.sh /usr/local/bin/budgie26
```

You can then start the complete desktop with:

```bash
budgie26 start
```

Manage the session with:

```bash
bash ubuntu-26.04-budgie.sh status
bash ubuntu-26.04-budgie.sh log
bash ubuntu-26.04-budgie.sh restart
bash ubuntu-26.04-budgie.sh stop
```

If the short command is installed, the same operations are simply `budgie26 status`, `budgie26 log`, `budgie26 restart`, and `budgie26 stop`.

### Change the desktop window size

WSLg exposes the nested Labwc desktop as a fixed output rather than a normal resizable application window. Change that output with the launcher:

```bash
bash ubuntu-26.04-budgie.sh size 1600x900
```

The launcher remembers the selected size and applies it again at the next start. Four readable presets are also available:

```bash
bash ubuntu-26.04-budgie.sh size small    # 1280x720
bash ubuntu-26.04-budgie.sh size medium   # 1440x810
bash ubuntu-26.04-budgie.sh size large    # 1600x900
bash ubuntu-26.04-budgie.sh size fullhd   # 1920x1080
```

Show the current and remembered size:

```bash
bash ubuntu-26.04-budgie.sh size
```

You can also select the size while starting or restarting:

```bash
bash ubuntu-26.04-budgie.sh start large
bash ubuntu-26.04-budgie.sh restart 1600x900
```

### Maximize the desktop

Maximize the Budgie window to the complete Windows work area with:

```bash
bash ubuntu-26.04-budgie.sh maximize
```

This uses the window's standard Windows maximize command, so mouse input stays aligned with the desktop. The Windows taskbar remains visible. The launcher remembers maximized mode and applies it again after a Budgie restart.

With the short command installed, the complete everyday sequence is:

```bash
budgie26 start
budgie26 maximize  # needed only once; the choice is remembered
```

Return to the normal window size with:

```bash
bash ubuntu-26.04-budgie.sh restore
```

Running a `size` command also restores normal windowed mode before applying the requested dimensions. For example:

```bash
bash ubuntu-26.04-budgie.sh size medium
```

The launcher uses `PrivateTmp=yes` for the service. This gives Labwc's Xwayland process a correct private `/tmp/.X11-unix` directory and avoids changing WSLg's read-only X11 socket mount. It links only WSLg's `X0` socket into that private directory so Labwc can use WSLg for its outer window while its own Xwayland server safely allocates another display.

### Why this launcher uses WSLg instead of X410

The Ubuntu 26.04 Budgie session is a wlroots/Labwc Wayland compositor. In testing, X410 did not provide the DRI3 or shared-memory path required by Labwc's nested X11 backend, so the compositor could not create an output. Launching `budgie-desktop` alone can show a panel and background, but it does not provide the Labwc window manager and therefore is not a complete session.

For Ubuntu Budgie 26.04, use this WSLg launcher. X410 remains useful for traditional X11 desktops and individual X11 applications, but it is not the renderer used by this script.

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

### Budgie opens but an old panel is still visible

An earlier manual `budgie-desktop` command may still be running outside the managed session. Close that old session, then run:

```bash
bash ubuntu-26.04-budgie.sh restart
```

The `doctor` command reports an unmanaged Budgie panel when it can detect one.

### The desktop window cannot be resized by dragging

The nested Labwc output may not expose a normal resize border through WSLg. Use the launcher's persistent size command instead:

```bash
bash ubuntu-26.04-budgie.sh size large
```

To fill the usable Windows screen while retaining correct mouse coordinates, use:

```bash
bash ubuntu-26.04-budgie.sh maximize
```

### Desktop icons cannot be moved freely

This is a Budgie version limitation rather than a WSL input problem. Ubuntu 26.04 currently ships Budgie Desktop View 10.10.2, which keeps desktop items in its automatically ordered grid. Upstream Budgie 10.10.3 introduces free placement of desktop icons.

Check the installed and available Ubuntu package versions with:

```bash
apt-cache policy budgie-desktop-view
```

When Ubuntu publishes version 10.10.3 or newer in the normal update repository, install it through the regular package updater. The launcher deliberately does not replace a core desktop component with an unverified source build.

### Portal, screencast, or `glamor` warnings in the log

WSLg may report that the host portal could not register an empty app ID, that the wlroots screencast portal is unavailable, or that Xwayland is falling back from `glamor` to software rendering. These warnings do not stop the desktop session. Use `status` to confirm that Labwc, Xwayland, and the Budgie panel remain active.

---

Return to the [main README](README.md).
