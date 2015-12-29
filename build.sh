#!/usr/bin/bash -x
export LANG=en_US.UTF-8
exec >/root/script-setup.log 2>&1

# Needs to be fully updated since the release data won't work with rpm-ostree
dnf update -y

# Install required packages
dnf install -y git rpm-ostree rpm-ostree-toolbox polipo docker fuse fuse-libs s3cmd python-pip gnupg

# Install pip
pip install yas3fs
pip install awscli

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

# Import private GPG key
rm -rf ~/.gnupg/
gpg --import /root/rpm_ostree/rpm_ostree_gpgkey.public
gpg --import /root/rpm_ostree/rpm_ostree_gpgkey.private

# Mount s3 volumes
mkdir /mnt/{repo,logs}
yas3fs -d s3://puiterwijk-atomic/repo/ /mnt/repo/
yas3fs -d s3://puiterwijk-atomic/logs/ /mnt/logs/

# TODO: Mount the polipo cache volume into /var/cache/polipo
# Start the caching daemon
systemctl start polipo.service

# Prepare the actual composing
mkdir -p /srv/rpm-ostree/{config,cache}

# Setup logging
LOGROOT="/mnt/logs/`date +%Y-%m-%d-%H:%M`"
mkdir $LOGROOT

# Remap logging
exec >$LOGROOT/script.log 2>&1
mv /root/script-setup.log $LOGROOT/script-setup.log

# Prepare composing
CONFIGDIR="/srv/rpm-ostree/config"
(
    cd $CONFIGDIR
    git show-ref HEAD >>$LOGROOT/clone.log 2>&1
    ./treefile-expander.py puiterwijk-trees-laptop.json.in >$LOGROOT/expander.log 2>&1
    cp puiterwijk-trees-laptop.json $LOGROOT/generated.json
)

# COMPOSE
# TODO: Enable compose
(
    cd /srv/rpm-ostree
    # rpm-ostree compose tree --repo=/mnt/repo --cachedir=/srv/rpm-ostree/cache $CONFIGDIR/puiterwijk-trees-laptop.json --proxy=http://localhost:8123/ >$LOGROOT/compose.log 2>&1
)

# Tear everything down again
# Sync data and write everything out
sync
umount /mnt/repo
# TODO: Unmount polipo cache
sync
# TODO: Enable self-termination
#shutdown --poweroff
#aws ec2 terminate-instances --instance-ids $AWS_INSTANCE_ID
