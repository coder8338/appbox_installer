# This is a work in progress, I am in the process of adding all apps.

# Appbox Installer
Appbox installer for radarr.

## How to run
1. Install the [Ubuntu 20.04 app](https://www.appbox.co/appstore/app/210)

2. Connect to your Ubuntu either through SSH or by the No VNC WebUI (and clicking the "Applications" menu, then "Terminal Emulator")

3. Enter the following `sudo bash -c "bash <(curl -Ls https://raw.githubusercontent.com/coder8338/appbox_installer/Ubuntu-20.04/appbox_installer.sh)"`

## How to manage services
To stop a service:

`s6-svc -d /run/s6/services/<service name>/`

To start a service:

`s6-svc -u /run/s6/services/<service name>/`

To restart a service:

`s6-svc -r /run/s6/services/<service name>/`

For example, to stop radarr you would run:

`s6-svc -d /run/s6/services/radarr/`

## How to view log files
The log for each service is found in `/var/log/appbox/` the format is: `/var/log/appbox/<service name>/current`

For example, if you wanted to view the log file for radarr you would run:

`cat /var/log/appbox/radarr/current`

## FAQs
Q: I want auto moving from my torrent client to anywhere using Radarr/Sonarr

A: You'll need to mirror the torrent client's directories using:

```
ln -s /APPBOX_DATA/apps/<TORRENT CLIENT>.<YOUR APPBOX NAME>.appboxes.co/torrents/ /torrents
ln -s /APPBOX_DATA/apps/ /torrents/home/apps
ln -s /APPBOX_DATA/storage/ /torrents/home/storage
```
