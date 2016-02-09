#!/usr/bin/bash -x
export LANG=en_US.UTF-8
export DATA_VOLID="vol-75f5cc86"
CONFIGDIR="/srv/rpm-ostree/config"
exec >/root/script-setup.log 2>&1
set -x

# Needs to be fully updated since the release data won't work with rpm-ostree
dnf update -y

# Install required packages
dnf install -y git rpm-ostree rpm-ostree-toolbox polipo docker fuse fuse-libs python-pip gnupg patch

# Install pip
pip install yas3fs
pip install awscli

# Apply patches
(
    cd /usr/lib/python2.*/site-packages/yas3fs/
    patch -p0 <$CONFIGDIR/yas3fs-sslfix.patch
)

# Retrieve credentials
export AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
export AWS_DEFAULT_REGION="${AVAILABILITY_ZONE:0:${#AVAILABILITY_ZONE} - 1}"
export AWS_INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
export CREDS="$(curl http://169.254.169.254/latest/meta-data/iam/security-credentials/puiterwijk-atomic)"
export AWS_ACCESS_KEY_ID="$(echo $CREDS | python3 -c 'import json,sys;obj=json.load(sys.stdin);print(obj["AccessKeyId"])')"
export AWS_SECRET_ACCESS_KEY="$(echo $CREDS | python3 -c 'import json,sys;obj=json.load(sys.stdin);print(obj["SecretAccessKey"])')"
export AWS_SESSION_TOKEN="$(echo $CREDS | python3 -c 'import json,sys;obj=json.load(sys.stdin);print(obj["Token"])')"

# Retrieve private info
aws s3 cp s3://puiterwijk-atomic-private/aws-keys /root/aws-keys
aws s3 cp s3://puiterwijk-atomic-private/rpm_ostree_gpgkey.public /root/rpm_ostree/rpm_ostree_gpgkey.public
aws s3 cp s3://puiterwijk-atomic-private/rpm_ostree_gpgkey.private /root/rpm_ostree/rpm_ostree_gpgkey.private

# Switch to permanent AWS keys
# (This is needed until BOTO understands AWS_SESSION_TOKEN)
source /root/aws-keys

# Attach Polipo cachge volume
aws ec2 attach-volume --volume-id $DATA_VOLID --instance-id $AWS_INSTANCE_ID --device /dev/xvdf
aws ec2 wait volume-in-use --volume-ids $DATA_VOLID
while [ ! -e /dev/xvdf ];
do
    echo "Waiting for data volume..."
    sleep 5
done
sleep 5
if [ ! -e /dev/xvdf1 ];
then
    echo "New drive, reformatting..."
    echo "n
    p
    1


    w
    "|fdisk /dev/xvdf
    mkfs.ext4 /dev/xvdf1
fi


# Import private GPG key
rm -rf ~/.gnupg/
gpg --import /root/rpm_ostree/rpm_ostree_gpgkey.public
gpg --import /root/rpm_ostree/rpm_ostree_gpgkey.private

# Mount s3 volumes
mkdir /mnt/{data,logs}
yas3fs -d s3://trees.puiterwijk.org/logs/ /mnt/logs/
mount /dev/xvdf1 /mnt/data
echo "Current disk usage: "
df -h /dev/xvdf1
mkdir -p /mnt/data/polipo
mkdir -p /mnt/data/repo
rmdir /var/cache/polipo
ln -s /mnt/data/polipo /var/cache/polipo
if [ -f /mnt/data/repo/config ];
then
    echo "Already synced"
else
    echo "Syncing"
    aws s3 sync s3://trees.puiterwijk.org/repo/ /mnt/data/repo/
fi
if [ ! -f /mnt/data/repo/config ];
then
    echo "Seems the repo was not yet initialized"
    ostree init --repo=/mnt/data/repo/ --mode=archive-z2
fi

# Start the caching daemon
systemctl start polipo.service

# Prepare the actual composing
mkdir -p /srv/rpm-ostree/{config,cache}

# Setup logging
LOGROOT="/mnt/logs/`date +%Y-%m-%d-%H:%M`"
mkdir $LOGROOT

# Remap logging
exec >$LOGROOT/script.log 2>&1
set -x
mv /root/script-setup.log $LOGROOT/script-setup.log

# Prepare composing
(
    cd $CONFIGDIR
    git show-ref HEAD >>$LOGROOT/clone.log 2>&1
    ./treefile-expander.py puiterwijk-trees-laptop.json.in >$LOGROOT/expander.log 2>&1
    cp puiterwijk-trees-laptop.json $LOGROOT/generated.json
    # For some weird reason, I need these manual imports...
    rpm --import 34EC9CBA.txt
    rpm --import copr-puiterwijk-atomic.gpg
)

# COMPOSE
(
    cd /srv/rpm-ostree
    mkdir /mnt/data/repo/{tmp,uncompressed-objects-cache,state}
    rpm-ostree compose tree --repo=/mnt/data/repo --cachedir=/srv/rpm-ostree/cache $CONFIGDIR/puiterwijk-trees-laptop.json --proxy=http://localhost:8123/ --touch-if-changed=/srv/rpm-ostree/changed >$LOGROOT/compose.log 2>&1
)

# Tear everything down again
# Stop polipo
systemctl stop polipo.service
echo "Post-compose disk usage: "
df -h /dev/xvdf1

# Upload repo
if [ -f /srv/rpm-ostree/changed ];
then
    echo "Changed. Syncing"
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
