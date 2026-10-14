# Credits and provenance

Classic desktop mode uses the systemd PID-namespace technique created for
[`Mattias Vinberg - StockHolm - sweden`](https://github.com/vinberg88/).

The upstream README states that the script may be used, changed, and
distributed. The upstream project is no longer maintained, so this repository
keeps an Ubuntu 24.04-specific compatibility mode and tests it separately from
modern native WSL systemd.

The files `start-systemd-namespace` and `enter-systemd-namespace` retain the
upstream command structure, including the Ubuntu 24.04-compatible
`--unit=basic.target` option. The installer and diagnostics in
`ubuntu-wsl2-systemd-script.sh` are maintained by this project.

<p align="center">
  <a href="https://github.com/vinberg88/ubuntu/">
 <img width="573" height="258" alt="ubuntu" src="https://github.com/user-attachments/assets/101e5e10-b099-4792-b995-037a2cd81c1c" />
</p>

See more desktops for Ubuntu =)
