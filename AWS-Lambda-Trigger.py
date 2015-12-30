from __future__ import print_function

import boto3

def lambda_handler(event, context):
    ec2 = boto3.resource('ec2')
    res = ec2.create_instances(ImageId="ami-080bd47b",
                               MinCount=1,
                               MaxCount=1,
                               Placement={
                                'AvailabilityZone': "eu-west-1c"
                               },
                               SecurityGroups=[
                                'puiterwijk-atomic-compose-server'
                               ],
                               InstanceType='t2.micro',
                               KeyName='test',
                               IamInstanceProfile={
                                'Arn': 'arn:aws:iam::757505437733:instance-profile/puiterwijk-atomic'
                               },
                               BlockDeviceMappings=[{
                                'DeviceName': '/dev/sda1',
                                'Ebs': {
                                    'VolumeSize': 10,
                                    'DeleteOnTermination': True,
                                    'VolumeType': 'gp2'
                                },
                               }],
                               UserData="""#cloud-config
runcmd:
- /bin/sh -c "curl https://raw.githubusercontent.com/puiterwijk/puiterwijk-Atomic/master/boot.sh | bash"
                               """)
    
    instance = res[0]
    instance.create_tags(Tags=[
        {
            "Key": "Name",
            "Value": "Puiterwijk-Atomic-Compose-Triggered"
        }
    ])

    return "Instance spun up: %s" % res
