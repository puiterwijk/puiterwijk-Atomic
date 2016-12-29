#!/usr/bin/bash -x
export LANG=en_US.UTF-8
GITURL="https://github.com/puiterwijk/puiterwijk-Atomic.git"
dnf install -y git
CONFIGDIR="/srv/rpm-ostree/config"
mkdir -p $CONFIGDIR
(
    git clone $GITURL $CONFIGDIR
)

# Make sure we always get the most recent build script
# (githubusercontent.com is cached)
source $CONFIGDIR/aws-prepare.sh
mv /root/script-setup.log $LOGROOT/prepare.log
source $CONFIGDIR/build.sh >$LOGROOT/build.log 2>&1
source $CONFIGDIR/aws-teardown.sh >$LOGROOT/teardown.log 2>&1
