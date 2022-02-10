# Android App Acquisition Script
Bash script to acquire data form Android apps

## Description
Script to acquire the private folder of an Android app (`/data/data/<app-name>`) as a `tar.gz` file, and adds the app version and a timestamp to the compressed filename. 

### Note
This scripts supports files and folder names with spaces on them (which happens on the `zoom` app).


### Examples

Acquire data with the wrong app name:
```
user@linux:~$ ./aquisition.sh us.zoom
[Info ] Does "us.zoom" exist?
[ERROR] "us.zoom" does not exist!
```

Acquire data with the correct app name:
```
user@linux:~$ ./aquisition.sh us.zoom.videomeetings
[Info ] Does "us.zoom.videomeetings" exist?
[Info ] Yes!
[Info ] Getting the version of "us.zoom.videomeetings"...
[Info ] The version is "5.9.3.4247".
[Info ] Copying data from "us.zoom.videomeetings" version "5.9.3.4247" ...
removing leading '/' from member names
data/user_de/0/us.zoom.videomeetings/
...
data/user/0/us.zoom.videomeetings/
...
[Info ] Copy terminated.
[Info ] Compressing "us.zoom.videomeetings--u0-v5.9.3.4247--2022.02.10T15.52.57.tar" ...
[Info ] Compressing terminated.
[Info ] Copying to local storage...
/sdcard/Download/us.zoom.videomeetings--u0-v5.9.3.4247--202....tar.gz: 1 file pulled. 25.8 MB/s (4590475 bytes in 0.170s)
[Info ] Copy terminated.
[Info ] Cleaning acquisition files from phone...
[Info ] Clean terminated.
```

Uncompress the acquired file:
```
user@linux:~$ gunzip us.zoom.videomeetings--u0-v5.9.3.4247--2022.02.10T16.18.12.tar.gz
user@linux:~$ tar -xvf us.zoom.videomeetings--u0-v5.9.3.4247--2022.02.10T16.18.12.tar
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
