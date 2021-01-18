# Appbox Installer
Appbox installer for VNC webui over SSL, radarr, sonarr, lidarr, bazarr, flexget, filebot, couchpotato, sickchill, medusa, lazylibrarian, nzbget, sabnzbdplus, ombi, jackett, synclounge, nzbhydra2, ngpost, pyload, organizr &amp; komga.

## How to run
1. Install the [Ubuntu VNC app](https://www.appbox.co/appstore/app/97)

2. Connect to your Ubuntu either through SSH or by the No VNC WebUI (and clicking the "Applications" menu, then "Terminal Emulator")

3. Enter the following `sudo bash -c "bash <(curl -Ls https://raw.githubusercontent.com/coder8338/appbox_installer/main/appbox_installer.sh)"`

## How to manage services
To stop a service:

`sudo supervisorctl stop <service name>`

To start a service:

`sudo supervisorctl start <service name>`

To restart a service:

`sudo supervisorctl restart <service name>`

For example, to stop radarr you would run:

`sudo supervisorctl stop radarr`

## How to view log files
The log for each service is found in `/tmp` the format is: `/tmp/<service name>.log`

For example, if you wanted to view the log file for radarr you would run:

`cat /tmp/radarr.log`

## FAQs
Q: I want auto moving from my torrent client to anywhere using Radarr/Sonarr

A: You'll need to mirror the torrent client's directories using:

```
ln -s /APPBOX_DATA/apps/<TORRENT CLIENT>.<YOUR APPBOX NAME>.appboxes.co/torrents/ /torrents
ln -s /APPBOX_DATA/apps/ /torrents/home/apps
ln -s /APPBOX_DATA/storage/ /torrents/home/storage
```
