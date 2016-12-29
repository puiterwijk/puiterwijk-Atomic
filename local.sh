#!/usr/bin/bash -x
export LANG=en_US.UTF-8
CONFIGDIR="/srv/rpm-ostree/config"

(
    cd $CONFIGDIR
    git pull
)

# Setup logging
export LOGROOT="/mnt/logs/`date +%Y-%m-%d-%H:%M`"
mkdir $LOGROOT

# Start the build
source $CONFIGDIR/build.sh >$LOGROOT/build.log 2>&1
