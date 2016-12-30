#!/usr/bin/bash -x
export LANG=en_US.UTF-8
export DATA_VOLID="vol-06fc33316bdd7ef83"
CONFIGDIR="/srv/rpm-ostree/config"
exec >/root/script-setup.log 2>&1
set -x

# Needs to be fully updated since the release data won't work with rpm-ostree
dnf update -y

# Install required packages
dnf install -y git rpm-ostree rpm-ostree-toolbox polipo docker fuse fuse-libs python-pip gnupg patch
# Polipo isn't in F25+. For that, I need to look at squid. Sometime.

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
set +x
export AWS_ACCESS_KEY_ID="$(echo $CREDS | python3 -c 'import json,sys;obj=json.load(sys.stdin);print(obj["AccessKeyId"])')"
export AWS_SECRET_ACCESS_KEY="$(echo $CREDS | python3 -c 'import json,sys;obj=json.load(sys.stdin);print(obj["SecretAccessKey"])')"
export AWS_SESSION_TOKEN="$(echo $CREDS | python3 -c 'import json,sys;obj=json.load(sys.stdin);print(obj["Token"])')"
set -x

# Retrieve private info
set +x
aws s3 cp s3://puiterwijk-atomic-private/aws-keys /root/aws-keys
aws s3 cp s3://puiterwijk-atomic-private/rpm_ostree_gpgkey.public /root/rpm_ostree/rpm_ostree_gpgkey.public
aws s3 cp s3://puiterwijk-atomic-private/rpm_ostree_gpgkey.private /root/rpm_ostree/rpm_ostree_gpgkey.private
set -x

# Switch to permanent AWS keys
# (This is needed until BOTO understands AWS_SESSION_TOKEN)
set +x
source /root/aws-keys
set -x

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

# Start the caching daemon
systemctl start polipo.service

# Setup logging
export LOGROOT="/mnt/logs/`date +%Y-%m-%d-%H:%M`"
mkdir $LOGROOT
