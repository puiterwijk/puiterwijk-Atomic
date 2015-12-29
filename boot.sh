#!/usr/bin/bash -x
export LANG=en_US.UTF-8
GITURL="https://github.com/puiterwijk/puiterwijk-Atomic.git"
dnf install -y git
CONFIGDIR="/srv/rpm-ostree/config"
(
    git clone $GITURL $CONFIGDIR
)

# Make sure we always get the most recent build script
source $CONFIGDIR/build.sh
