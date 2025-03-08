# Android App Acquisition Script
Bash script to acquire data form Android apps

## Description
Script to acquire (copy) the folders of an Android app as a `tgz` file, and adds the app version and a timestamp to the compressed filename.



### Usage

```
./acquisition.sh <app_name> [-d|-e]
    -e Emulator (default)
    -d Physical device via USB
```

> **Note**
>
> This scripts supports files and folder names with spaces on them (which happens with the `telegram` app).


### Requirements

This script requires:
- `adb` to install do: `sudo apt install adb`
- `tar` (pre-installed in most Linux distros)
- `gzip` (pre-installed in most Linux distros)

This script was developed and tested on Ubuntu 22.04 and Android 11.


### Examples

Acquire data with the wrong app name, or non-existing:
```
user@linux:~$ ./acquisition.sh zoom
[Info ] Acquiring from device: emulator
[Info ] Android version = 11
[ERROR] No matches found for: "zoom"
```

Too many matches for the app name:
```
user@linux:~$ ./acquisition.sh google
[Info ] Acquiring from device: emulator
[Info ] Android version = 11
com.google.android.networkstack.tethering
com.google.android.youtube
com.google.android.ext.services
com.google.android.googlequicksearchbox
com.google.android.cellbroadcastservice
com.google.android.onetimeinitializer
...
[WARN ] 60 matches found.
[WARN ] Exiting!
```

Acquire data from an existing app:
```
user@linux:~$ ./aquisition.sh telegram
[Info ] Acquiring from device: emulator
[Info ] Android version = 11
[Info ] App found: org.telegram.messenger
data/media/0/Android/media/org.telegram.messenger/Telegram/Telegram Video/
...
[Info ] Compressing terminated.
[Info ] Copying to local storage...
/sdcard/Download/org.telegram.messenger-v11.7.4--emu11--2025.03.08T19.47.15.tgz: 1 file pulled. 430.6 MB/s (175406870 bytes in 0.388s)
[Info ] Copy terminated.
[Info ] Cleaning acquisition files from phone...
[Info ] Clean terminated.
```

Uncompress the acquired file:
```
user@linux:~$ tar -xvzf org.telegram.messenger-v11.7.4--emu11--2025.03.08T19.47.15.tgz
data/media/0/Android/media/org.telegram.messenger/Telegram/
data/media/0/Android/media/org.telegram.messenger/Telegram/Telegram Images/
data/media/0/Android/media/org.telegram.messenger/Telegram/Telegram Video/
data/media/0/Android/media/org.telegram.messenger/Telegram/
data/media/0/Android/media/org.telegram.messenger/Telegram/Telegram Images/
data/media/0/Android/media/org.telegram.messenger/Telegram/Telegram Video/
data/media/0/Android/media/org.telegram.messenger/Telegram/Telegram Images/
data/media/0/Android/media/org.telegram.messenger/Telegram/Telegram Video/
...
```

Verify the folder structure of the acquired data:
```
user@linux:~$ tree -d -L 7
.
├── data
│   └── media
│       └── 0
│           └── Android
│               ├── data
│               │   └── org.telegram.messenger
│               │       ├── cache
│               │       └── files
│               └── media
│                   └── org.telegram.messenger
│                       └── Telegram
└── data_mirror
    └── data_ce
        └── 1b1c9724-5b54-4dee-97b6-6644091b138c
            └── 0
                └── org.telegram.messenger
                    ├── cache
                    ├── code_cache
                    ├── databases
                    ├── files
                    │   ├── account1
                    │   ├── account2
                    │   ├── account3
                    │   └── ShortcutInfoCompatSaver_share_targets
                    ├── no_backup
                    └── shared_prefs

26 directories
```
