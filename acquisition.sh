#!/usr/bin/env bash

ADB=/usr/bin/adb


if [[ $# -lt 1 ]]; then
    echo "Usage:"
    echo "      $0 app.full.name [-d|-e]"
    echo ""
    echo "example:"
    echo "      $0 com.google.android.inputmethod.latin      # acquire from emulator"
    echo "      $0 com.google.android.inputmethod.latin -d   # acquire USB device"
    exit
fi

SEARCH_TERM=$1


DEVICE=${2:--e}
# options:
#   -e = emulator (default)
#   -d = usb connected


case $DEVICE in

  "-e")
    # default option (tested with AVD)
    echo "[Info ] Acquiring from device: emulator"
    DEVNAME="emu"
    ;;

  "-d")
    # must be specified (only tested with Samsung A40)
    echo "[Info ] Acquiring from device: USB"
    DEVNAME="usb"
    ;;

  *)
    echo "[ERROR] Unknown device \"$DEVICE\""
    exit;
    ;;
esac



# Get Android version
ANDROID_VERSION=$(adb shell getprop ro.build.version.release)

# Extract the major version number (before the first dot, if present)
ANDROID=$(echo "$ANDROID_VERSION" | cut -d'.' -f1)
echo "[Info ] Android version = $ANDROID"


# Check if version is 9 or below
# this needs more testing
if [ "$ANDROID" -le 9 ]; then
    CMD="su 0"
    END=""
else
    CMD="su -c '"
    END="'"
fi


# Get matching packages
MATCHES=$(adb shell pm list packages | grep "$SEARCH_TERM" | cut -d: -f2)


# Count the number of matches
MATCH_COUNT=$(echo "$MATCHES" | wc -l)

if [ -z "$MATCHES" ]; then
    echo "[ERROR] No matches found for: \"$SEARCH_TERM\""
    exit
fi


if [ "$MATCH_COUNT" -eq 1 ]; then
    APP=$MATCHES
    echo "[Info ] App found: $APP"

elif [ "$MATCH_COUNT" -ge 2 ]; then
    echo "$MATCHES"
    echo "[WARN ] $MATCH_COUNT matches found."
    echo "[WARN ] Exiting!"
    exit

else
    echo "[ERROR] No matches found for: \"$SEARCH_TERM\""
    exit
fi


echo "[Info ] Getting info..."
    VERSION=$(adb $DEVICE shell dumpsys package $APP | grep versionName | cut -d= -f2)
    FILENAME="$APP-v$VERSION--$DEVNAME$ANDROID--$(date '+%Y.%m.%dT%H.%M.%S')"
echo "[Info ] $APP version = $VERSION"


echo "[Info ] Finding data from \"$APP\" ..."


    SEARCH_FOLDERS=(
#                     "/" # Too slow
                    "/data_mirror/data_ce/"
                    "/data/media/"
                    "/data/user_de/"
                    "/data/user/"
                    "/storage/emulated/"
                    )

    # Declare an associative array to keep track of the inodes
    declare -A seen_inodes

    # search all folders with $APP name
    for FOLDER in "${SEARCH_FOLDERS[@]}"; do
        # Capture the find result and split it into separate array entries
        while IFS= read -r FOLDER_RESULT; do
            FOUND_FOLDERS+=("$FOLDER_RESULT")
        done < <($ADB $DEVICE shell "$CMD find $FOLDER -type d -name $APP 2>/dev/null $END")
    done



    # List the files inside the found folders
    echo "------------------------"
    for FOLDER in "${FOUND_FOLDERS[@]}"; do

        # Test if a folder is a mapping of another one
        # to avoid duplication and loops
        INODE=$($ADB $DEVICE shell "$CMD stat -c %i '$FOLDER' $END")
        # Check if the inode is already seen
        if [ -z "${seen_inodes[$INODE]}" ]; then
            # If not, add the folder contents to the list of files and mark the inode as seen
            echo "[Info ] Adding folder: $FOLDER"
            seen_inodes[$INODE]=1  # Mark this inode as seen
            $ADB $DEVICE shell "$CMD find $FOLDER -print0 >> /sdcard/Download/$FILENAME.txt $END"
        fi
    done
    echo "------------------------"


echo "[Info ] Compressing data from \"$APP\" ..."
    $ADB $DEVICE shell "$CMD cat /sdcard/Download/$FILENAME.txt | xargs -0 tar -cvzf /sdcard/Download/$FILENAME.tgz $END"
echo "[Info ] Compressing terminated."

echo "[Info ] Copying to local storage..."
    $ADB $DEVICE pull /sdcard/Download/$FILENAME.tgz .
echo "[Info ] Copy terminated."


echo "[Info ] Cleaning acquisition files from phone..."
    $ADB $DEVICE shell rm /sdcard/Download/$FILENAME.tgz
    $ADB $DEVICE shell rm /sdcard/Download/$FILENAME.txt
echo "[Info ] Clean terminated."
