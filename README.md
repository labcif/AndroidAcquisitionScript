# Android App Acquisition Script
Bash script to acquire data form Android apps

## Description
Script to acquire the private folder of an Android app (`/data/data/<app-name>`) as a `tar.gz` file, and adds the app version and a timestamp to the compressed filename. 

> **Note**
>
> This scripts supports files and folder names with spaces on them (which happens on the `zoom` app).


### Requirements

This script requires:
- `adb` to install do: `sudo apt install adb`
- `tar` (pre-installed in most Linux distros)
- `gzip` (pre-installed in most Linux distros)

This script was developed and tested on Ubuntu 20.04 and Android 10.


### Examples

Acquire data with the wrong app name:
```
user@linux:~$ ./aquisition.sh us.zoom
[Info ] Does "us.zoom" exist?
[ERROR] "us.zoom" does not exist!
```

Acquire data with the correct app name:
```
user@linux:~$ ./aquisition.sh us.zoom.videomeetings -d
[Info ] Acquiring from device: USB
[Info ] Does "us.zoom.videomeetings" exist?
[Info ] Yes!
[Info ] Getting info...
[Info ] us.zoom.videomeetings version = 5.9.6.4756
[Info ] Android version = 10
[Info ] Copying data from "us.zoom.videomeetings" version "5.9.6.4756" ...
removing leading '/' from member names
data/user_de/0/us.zoom.videomeetings/
...
data/user/0/us.zoom.videomeetings/
...
[Info ] Copy terminated.
[Info ] Compressing "us.zoom.videomeetings-v5.9.6.4756--usb10--u0--2022.03.14T17.01.42.tar" ...
[Info ] Compressing terminated.
[Info ] Copying to local storage...
/sdcard/Download/us.zoom.videomeetings-v5.9.6.4756--....z: 1 file pulled. 25.3 MB/s (4572767 bytes in 0.173s)
[Info ] Copy terminated.
[Info ] Cleaning acquisition files from phone...
[Info ] Clean terminated.
```

Uncompress the acquired file:
```
user@linux:~$ gunzip us.zoom.videomeetings-v5.9.6.4756--usb10--u0--2022.03.14T17.01.42.tar.gz
user@linux:~$ tar -xvf us.zoom.videomeetings-v5.9.6.4756--usb10--u0--2022.03.14T17.01.42.tar
data/user_de/0/us.zoom.videomeetings/
data/user_de/0/us.zoom.videomeetings/code_cache/
data/user_de/0/us.zoom.videomeetings/code_cache/com.android.skia.shaders_cache
data/user_de/0/us.zoom.videomeetings/code_cache/com.android.opengl.shaders_cache
data/user_de/0/us.zoom.videomeetings/cache/
data/user/0/us.zoom.videomeetings/
data/user/0/us.zoom.videomeetings/data/
...
```

Verify the folder structure of the acquired data:
```
user@linux:~$ tree -d -L 4 data/
data/
├── user
│   └── 0
│       └── us.zoom.videomeetings
│           ├── cache
│           ├── code_cache
│           ├── data
│           ├── files
│           ├── no_backup
│           └── shared_prefs
└── user_de
    └── 0
        └── us.zoom.videomeetings
            ├── cache
            └── code_cache

14 directories
```
