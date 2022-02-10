# AndroidAcquisitionScript
Bash script to acquire data form Android apps

## Description
Script to acquire the private folder of an Android app (`/data/data/<app-name>`) as a `tar.gz` file, and adds the app version and a timestamp to the compressed filename. 

### Important
This scripts supports files and folder names with spaces on them (which happens on the `zoom` app).


### Example


Wrong app name:
```
user@linux:~$ ./aquisition.sh us.zoom
[Info ] Does "us.zoom" exists?
[ERROR] "us.zoom" does not exists!
```

Correct app name:
```
user@linux:~$ ./aquisition.sh us.zoom.videomeetings
[Info ] Does "us.zoom.videomeetings" exists?
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

