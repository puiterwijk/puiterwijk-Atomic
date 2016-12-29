#!/usr/bin/bash -x
# Tear everything down again
# Stop polipo
systemctl stop polipo.service
echo "Post-compose disk usage: "
df -h /dev/xvdf1

# Upload repo
if [ -f /srv/rpm-ostree/changed ];
then
    echo "Changed. Syncing"
    echo "Changed" >$LOGROOT/changed
    rm -rf /mnt/data/repo/{tmp,uncompressed-objects-cache,state}
    aws s3 sync /mnt/data/repo s3://trees.puiterwijk.org/repo/ --acl public-read --delete
else
    echo "Not changed"
fi

# Upload published info
aws s3 sync /srv/rpm-ostree/config/published s3://trees.puiterwijk.org/ --acl public-read

# Sync data and write everything out
sync
umount /mnt/data

# Self-termination
aws ec2 terminate-instances --instance-ids $AWS_INSTANCE_ID
