# Credits and provenance

Classic desktop mode uses the systemd PID-namespace technique created for
[`DamionGans/ubuntu-wsl2-systemd-script`](https://github.com/DamionGans/ubuntu-wsl2-systemd-script).

The upstream README states that the script may be used, changed, and
distributed. The upstream project is no longer maintained, so this repository
keeps an Ubuntu 24.04-specific compatibility mode and tests it separately from
modern native WSL systemd.

The files `start-systemd-namespace` and `enter-systemd-namespace` retain the
upstream command structure, including the Ubuntu 24.04-compatible
`--unit=basic.target` option. The installer and diagnostics in
`ubuntu-wsl2-systemd-script.sh` are maintained by this project.

Original work was based on instructions from the
[Snapcraft forum](https://forum.snapcraft.io/t/running-snaps-on-wsl2-insiders-only-for-now/13033).
