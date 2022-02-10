#!/usr/bin/env bash

ADB=/usr/bin/adb
USER=0


if [[ $# -ne 1 ]]; then
    echo "Usage:"
    echo "      $0 app.full.name"
    echo ""
    echo "example:"
    echo "      $0 com.google.android.inputmethod.latin"
    exit
fi

APP=$1


echo "[Info ] Does \"$APP\" exist?"
    IsDir=`adb shell "su -c 'ls /data/user/$USER/$APP'" &> /dev/null ; echo "$?"`
    if [ $IsDir != 0 ] ; then 
        echo "[ERROR] \"$APP\" does not exist!"
        exit;
    fi
echo "[Info ] Yes!"


echo "[Info ] Getting the version of \"$APP\"..."
    VERSION=$(adb shell dumpsys package $APP | grep versionName | cut -d= -f2)
    FILENAME="$APP--u$USER-v$VERSION--$(date '+%Y.%m.%dT%H.%M.%S').tar"
echo "[Info ] The version is \"$VERSION\"."


echo "[Info ] Copying data from \"$APP\" version \"$VERSION\" ..."
    # does not support filenames with spaces
    #$ADB shell "su -c 'tar -cvzf /sdcard/Download/$FILENAME /data/user/$USER/$APP /data/user_de/$USER/$APP'"

    # supports filenames with spaces
    $ADB shell "su -c 'find /data/user_de/$USER/$APP -print0 > /sdcard/Download/$FILENAME.1.txt'"
    $ADB shell "su -c 'find /data/user/$USER/$APP -print0 > /sdcard/Download/$FILENAME.2.txt'"
    $ADB shell "su -c 'tar -cvzf /sdcard/Download/$FILENAME -T /sdcard/Download/$FILENAME.1.txt -T /sdcard/Download/$FILENAME.2.txt'" 
echo "[Info ] Copy terminated."


echo "[Info ] Compressing \"$FILENAME\" ..."
    $ADB shell gzip /sdcard/Download/$FILENAME
echo "[Info ] Compressing terminated."


echo "[Info ] Copying to local storage..."
    $ADB pull /sdcard/Download/$FILENAME.gz .
echo "[Info ] Copy terminated."


echo "[Info ] Cleaning acquisition files from phone..."
    $ADB shell rm /sdcard/Download/$FILENAME.gz
    $ADB shell rm /sdcard/Download/$FILENAME.?.txt
echo "[Info ] Clean terminated."
