#!/usr/bin/env bash

ADB=/usr/bin/adb
USER=0


if [[ $# -lt 1 ]]; then
    echo "Usage:"
    echo "      $0 app.full.name [-d|-e]"
    echo ""
    echo "example:"
    echo "      $0 com.google.android.inputmethod.latin      # acquire from emulator"
    echo "      $0 com.google.android.inputmethod.latin -d   # acquire USB device"
    exit
fi

APP=$1


DEVICE=${2:--e}
# options:
#   -e = emulator (default)
#   -d = usb connected


case $DEVICE in

  "-e")
    # default option (tested with AVD)
    echo "[Info ] Acquiring from device: emulator"
    CMD="su 0"
    END=""
    DEVNAME="emu"
    ;;

  "-d")
    # must be specified (only tested with Samsung A40)
    echo "[Info ] Acquiring from device: USB"
    CMD="su -c '"
    END="'"
    DEVNAME="usb"
    ;;

  *)
    echo "[ERROR] Unknown device \"$DEVICE\""
    exit;
    ;;
esac


echo "[Info ] Does \"$APP\" exist?"
    IsDir=`adb $DEVICE shell echo "ls /data/user/$USER/$APP" \| su &> /dev/null ; echo "$?"`
    if [ $IsDir != 0 ] ; then 
        echo "[ERROR] \"$APP\" does not exist!"
        exit;
    fi
echo "[Info ] Yes!"


echo "[Info ] Getting info..."
    VERSION=$(adb $DEVICE shell dumpsys package $APP | grep versionName | cut -d= -f2)
    ANDROID=$(adb $DEVICE shell getprop ro.build.version.release)
    FILENAME="$APP--$DEVNAME$ANDROID--u$USER-v$VERSION--$(date '+%Y.%m.%dT%H.%M.%S').tar"
echo "[Info ] $APP version = $VERSION"
echo "[Info ] Android version = $ANDROID"


echo "[Info ] Copying data from \"$APP\" version \"$VERSION\" ..."
    # does not support filenames with spaces
    #$ADB shell "su -c 'tar -cvzf /sdcard/Download/$FILENAME /data/user/$USER/$APP /data/user_de/$USER/$APP'"

    # supports filenames with spaces
    $ADB $DEVICE shell "$CMD find /data/user_de/$USER/$APP -print0 > /sdcard/Download/$FILENAME.1.txt $END"
    $ADB $DEVICE shell "$CMD find /data/user/$USER/$APP -print0 > /sdcard/Download/$FILENAME.2.txt $END"
    $ADB $DEVICE shell "$CMD tar -cvzf /sdcard/Download/$FILENAME -T /sdcard/Download/$FILENAME.1.txt -T /sdcard/Download/$FILENAME.2.txt $END" 
echo "[Info ] Copy terminated."


echo "[Info ] Compressing \"$FILENAME\" ..."
    $ADB $DEVICE shell gzip /sdcard/Download/$FILENAME
echo "[Info ] Compressing terminated."


echo "[Info ] Copying to local storage..."
    $ADB $DEVICE pull /sdcard/Download/$FILENAME.gz .
echo "[Info ] Copy terminated."


echo "[Info ] Cleaning acquisition files from phone..."
    $ADB $DEVICE shell rm /sdcard/Download/$FILENAME.gz
    $ADB $DEVICE shell rm /sdcard/Download/$FILENAME.?.txt
echo "[Info ] Clean terminated."
