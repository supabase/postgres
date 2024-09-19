import os
import boto3
import time
from ec2instanceconnectcli.ec2instanceconnectcli import EC2InstanceConnectCLI

# Initialize boto3 clients
ec2_client = boto3.client('ec2')
ec2_resource = boto3.resource('ec2')

# Get the AMI name from environment variable
AMI_NAME = os.environ.get('PRE_AMI_NAME')

def launch_temporary_instance():
    # Describe the AMI
    images = ec2_client.describe_images(Owners=['self'], Filters=[{'Name': 'name', 'Values': [AMI_NAME]}])
    if not images['Images']:
        raise Exception(f"No AMI found with name: {AMI_NAME}")
    image_id = images['Images'][0]['ImageId']

    # Launch the instance
    instance = ec2_resource.create_instances(
        ImageId=image_id,
        InstanceType='t4g.micro',
        MinCount=1,
        MaxCount=1,
        TagSpecifications=[
            {
                'ResourceType': 'instance',
                'Tags': [{'Key': 'Name', 'Value': 'AMI-Resize-Temp'}]
            }
        ]
    )[0]

    print(f"Launched instance: {instance.id}")
    return instance.id

def wait_for_instance_running(instance_id):
    instance = ec2_resource.Instance(instance_id)
    instance.wait_until_running()
    print(f"Instance {instance_id} is now running")

def resize_filesystem(instance_id):
    cli = EC2InstanceConnectCLI()
    command = "sudo e2fsck -f /dev/sda1 && sudo resize2fs /dev/sda1 8G && sudo sync"
    cli.start_session(instance_id=instance_id, command=command)

def create_new_ami(instance_id):
    new_ami_name = f"supabase-postgres-{os.environ.get('GITHUB_RUN_ID', 'resized')}"
    response = ec2_client.create_image(
        InstanceId=instance_id,
        Name=new_ami_name,
        Description="Resized AMI"
    )
    new_ami_id = response['ImageId']
    print(f"Created new AMI: {new_ami_id} with name: {new_ami_name}")
    return new_ami_id, new_ami_name

def wait_for_ami_available(ami_id):
    waiter = ec2_client.get_waiter('image_available')
    waiter.wait(ImageIds=[ami_id])
    print(f"AMI {ami_id} is now available")

def modify_ami_block_device_mapping(ami_id):
    ec2_client.modify_image_attribute(
        ImageId=ami_id,
        BlockDeviceMappings=[
            {
                'DeviceName': '/dev/sda1',
                'Ebs': {'VolumeSize': 8}
            }
        ]
    )
    print(f"Modified block device mapping for AMI {ami_id}")

def terminate_instance(instance_id):
    ec2_resource.Instance(instance_id).terminate()
    print(f"Terminated instance {instance_id}")

def main():
    try:
        instance_id = launch_temporary_instance()
        wait_for_instance_running(instance_id)
        resize_filesystem(instance_id)
        new_ami_id, new_ami_name = create_new_ami(instance_id)
        wait_for_ami_available(new_ami_id)
        modify_ami_block_device_mapping(new_ami_id)
    finally:
        if 'instance_id' in locals():
            terminate_instance(instance_id)

    print(f"NEW_AMI_ID={new_ami_id}")
    print(f"NEW_AMI_NAME={new_ami_name}")

if __name__ == "__main__":
    main()