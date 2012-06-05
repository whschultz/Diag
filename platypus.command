#!/bin/sh

export LAUNCHED="$0"

export LOCATION="$(dirname "$LAUNCHED")"

#export PATH="$LOCATION:$PATH"

echo "This script needs root access in order to look for faults in other users' home directories."

sudo PATH="$LOCATION:$PATH" "$LOCATION/diag" -a -l -i # -d afsc -d full -d unplug -d 2nd

echo " -- done --"
echo "Print this window to PDF if you wish to send the results to someone for review."
echo "Sleeping in order to keep the window open..."

sleep 18000 # five hours
