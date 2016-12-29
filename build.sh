#!/usr/bin/bash -x
# Expectations:
#  $LOGROOT - env var to where logs for this run should be stored
#  $CONFIGDIR - env var to where the rpm-ostree config is checked out
#  /mnt/data/repo/ - directory where the rpm-ostree repo is stored
#  /srv/rpm-ostree - directory with some temporary free space
#  localhost:8123 - caching proxy
# Log system information
cat /etc/redhat-release >$LOGROOT/system-version 2>&1
yum list installed >$LOGROOT/system-packages 2>&1

# Prepare composing
(
    cd $CONFIGDIR
    git show-ref HEAD >>$LOGROOT/clone.log 2>&1
    ./treefile-expander.py puiterwijk-trees-laptop.json.in >$LOGROOT/expander.log 2>&1
    cp puiterwijk-trees-laptop.json $LOGROOT/generated.json
    # For some weird reason, I need these manual imports...
    rpm --import 81B46521.txt
)

# COMPOSE
(
    cd /srv/rpm-ostree
    mkdir -p /mnt/data/repo/{tmp,uncompressed-objects-cache,state}
    rpm-ostree compose tree --repo=/mnt/data/repo --cachedir=/srv/rpm-ostree/cache $CONFIGDIR/puiterwijk-trees-laptop.json --proxy=http://localhost:8123/ --touch-if-changed=/srv/rpm-ostree/changed >$LOGROOT/compose.log 2>&1
)
