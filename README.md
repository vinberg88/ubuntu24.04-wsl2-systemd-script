# Ubuntu 24.04 WSL2 Systemd — Start Desktops with X410

Start a complete **Ubuntu 24.04 Budgie desktop** through **X410** on WSL2.
The Classic mode in this repository preserves the X410 `DISPLAY` value while
entering the systemd namespace required by the desktop session.

> [!IMPORTANT]
> Ubuntu 26.04 has a separate, tested WSLg launcher. Use
> [`ubuntu26.04-wsl2-budgie`](https://github.com/vinberg88/ubuntu26.04-wsl2-budgie)
> for Ubuntu 26.04.

## Which mode should I use?

| Goal | Recommended mode |
| --- | --- |
| Start the complete Ubuntu 24.04 Budgie desktop with X410 | **Classic Budgie** |
| Run ordinary services or individual WSLg applications | Native WSL systemd |

Classic Budgie mode is the default because it reproduces the systemd namespace
environment that has been verified to start Budgie on Ubuntu 24.04.

The installer prevents Classic and native systemd from running together. Two
simultaneous systemd environments compete for the user D-Bus and runtime
sockets, which can stop Budgie from starting.

## Install Classic Budgie mode

Start X410 in Windows first. Use the X410 window or desktop mode that normally
works on your computer. Do not manually replace a working `DISPLAY` value.

Then open Windows PowerShell and update WSL:

```powershell
wsl --update
wsl --list --verbose
```

Confirm that Ubuntu 24.04 uses WSL version `2`. Then open Ubuntu 24.04 and run:

```bash
sudo apt update
sudo apt install -y git mesa-utils daemonize util-linux-extra ubuntu-budgie-desktop
git clone https://github.com/vinberg88/ubuntu24.04-wsl2-systemd-script.git
cd ubuntu24.04-wsl2-systemd-script
bash ubuntu-wsl2-systemd-script.sh
```

The default command installs Classic Budgie mode and sets
`systemd=false` in `/etc/wsl.conf`. Close Ubuntu and run:

```powershell
wsl --shutdown
```

Start X410 again if it is not already running, then open Ubuntu and verify the
complete environment:

```bash
cd ~/ubuntu24.04-wsl2-systemd-script
bash ubuntu-wsl2-systemd-script.sh --check
printf 'DISPLAY=%s\n' "$DISPLAY"
```

A correct Classic installation reports:

```text
/etc/wsl.conf systemd: false
Classic Bash hook: installed
[OK] Classic Budgie systemd namespace is active without native systemd.
Result: ready (0 warning(s))
```

The `DISPLAY` line must contain the X410 display selected by your Windows/WSL
setup. The Classic helper copies this value into `~/.systemd-env`, so Budgie and
programs started inside the namespace continue to use X410.

You can then start Budgie:

```bash
budgie-desktop
```

Keep that Ubuntu terminal open while the desktop is running.

## Commands

| Command | Purpose |
| --- | --- |
| `bash ubuntu-wsl2-systemd-script.sh` | Install Classic Budgie mode |
| `bash ubuntu-wsl2-systemd-script.sh --classic-budgie` | Same as the default command |
| `bash ubuntu-wsl2-systemd-script.sh --check` | Diagnose systemd, D-Bus, display, and conflicts |
| `bash ubuntu-wsl2-systemd-script.sh --native` | Remove Classic mode and enable native WSL systemd |
| `bash ubuntu-wsl2-systemd-script.sh --help` | Show all options |

## Return to native WSL systemd

If you no longer need the Classic Budgie environment, run:

```bash
cd ~/ubuntu24.04-wsl2-systemd-script
bash ubuntu-wsl2-systemd-script.sh --native
```

Then close Ubuntu and run `wsl --shutdown` from Windows PowerShell. This removes
the Classic Bash hook and enables `systemd=true` in `/etc/wsl.conf`.

## Troubleshooting

### Budgie does not start

Run:

```bash
bash ubuntu-wsl2-systemd-script.sh --check
```

If the check says that native and Classic systemd are running together,
reinstall Classic mode and restart WSL:

```bash
bash ubuntu-wsl2-systemd-script.sh --classic-budgie
```

Then run `wsl --shutdown` from Windows PowerShell.

### `Cannot open display` or an empty `DISPLAY`

Close Ubuntu, start X410 in Windows, and open Ubuntu again. Check the value
before starting Budgie:

```bash
printf 'DISPLAY=%s\n' "$DISPLAY"
```

Do not hard-code `DISPLAY=:0` unless that is the value supplied by your working
X410 configuration. The script deliberately keeps the value inherited from
Windows/WSL.

### `Transport endpoint is not connected`

This normally means two systemd user managers have competed for
`/run/user/<uid>`. Reinstall Classic mode, shut down WSL completely, and open
Ubuntu again.

### `$'\r': command not found`

Update the checkout:

```bash
git pull --ff-only
```

The repository's `.gitattributes` keeps shell scripts in Unix LF format.

### OpenGL reports `llvmpipe`

Install Mesa's diagnostic tool and test WSL's D3D12 renderer:

```bash
sudo apt install -y mesa-utils
GALLIUM_DRIVER=d3d12 glxinfo -B
```

## Origin of Classic mode

The working namespace method comes from
[`DamionGans/ubuntu-wsl2-systemd-script`](https://github.com/DamionGans/ubuntu-wsl2-systemd-script).
That project is no longer maintained, so this repository provides an Ubuntu
24.04-specific installer, conflict detection, and a clean native-mode switch.
See [CREDITS.md](CREDITS.md) for provenance.

## Included files

| File | Purpose |
| --- | --- |
| `ubuntu-wsl2-systemd-script.sh` | Installs, removes, and diagnoses Classic or native systemd |
| `start-systemd-namespace` | Starts or enters the Classic systemd namespace |
| `enter-systemd-namespace` | Creates and enters the Classic PID namespace |
| `CREDITS.md` | Original project attribution |
| `UBUNTU-26.04.md` | Redirect to the separate Ubuntu 26.04 repository |
| `ubuntu-26.04-budgie.sh` | Compatibility copy only; use the Ubuntu 26.04 repository |
