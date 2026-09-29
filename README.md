# ubuntu-wsl2-systemd-script for UBUNTU 24.04

Script to enable systemd support on current Ubuntu 24.04 images WSL image. 

<img width="1037" height="271" alt="10054" src="https://github.com/user-attachments/assets/8f6ec452-287a-400b-84b2-d73a2a012faf" />

## Usage
You need ```git``` to be installed for the commands below to work. Use
```sh
sudo apt install git
```
to do so.
### Run the script and commands
```sh
git clone https://github.com/DamionGans/ubuntu-wsl2-systemd-script.git
cd ubuntu-wsl2-systemd-script/
bash ubuntu-wsl2-systemd-script.sh
# Enter your password and wait until the script has finished
```
### Then restart the Ubuntu shell and try running systemctl
```sh
systemctl

```
If you don't get an error and see a list of units, the script worked.

Have fun using systemd on your Ubuntu WSL2 image. You may use and change and distribute this script in whatever way you'd like. 
