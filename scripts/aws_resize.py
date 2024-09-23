import os
import boto3
import time
import socket
import logging
from ec2instanceconnectcli.EC2InstanceConnectLogger import EC2InstanceConnectLogger
from ec2instanceconnectcli.EC2InstanceConnectKey import EC2InstanceConnectKey

# Initialize boto3 clients
ec2_client = boto3.client('ec2', region_name="ap-southeast-1")
ec2_resource = boto3.resource('ec2', region_name="ap-southeast-1")

# Set up logging
logger = logging.getLogger("ami-resize")
handler = logging.StreamHandler()
formatter = logging.Formatter('%(asctime)s %(name)-12s %(levelname)-8s %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)
logger.setLevel(logging.DEBUG)

def launch_temporary_instance():
    AMI_NAME = os.environ.get('PRE_AMI_NAME')
    logger.info(f"Searching for AMI with name: {AMI_NAME}")
    images = ec2_client.describe_images(Owners=['self'], Filters=[{'Name': 'name', 'Values': [AMI_NAME]}])
    logger.debug(f"Describe images response: {images}")
    if not images['Images']:
        raise Exception(f"No AMI found with name: {AMI_NAME}")
    image_id = images['Images'][0]['ImageId']
    logger.info(f"Found AMI: {image_id}")

    instance = ec2_resource.create_instances(
        ImageId=image_id,
        InstanceType='t4g.micro',
        MinCount=1,
        MaxCount=1,
        TagSpecifications=[
            {
                'ResourceType': 'instance',
                'Tags': [
                    {'Key': 'Name', 'Value': 'AMI-Resize-Temp'},
                    {'Key': 'creator', 'Value': 'ami-resize-script'},
                    {'Key': 'resize-run-id', 'Value': os.environ.get("GITHUB_RUN_ID", "local-run")}
                ]
            }
        ],
        NetworkInterfaces=[
            {
                'DeviceIndex': 0,
                'AssociatePublicIpAddress': True,
                'Groups': ["sg-0a883ca614ebfbae0", "sg-014d326be5a1627dc"],
            }
        ],
    )[0]

    logger.info(f"Launched instance: {instance.id}")
    return instance.id

def wait_for_instance_running(instance_id):
    instance = ec2_resource.Instance(instance_id)
    instance.wait_until_running()
    logger.info(f"Instance {instance_id} is now running")


    while not instance.public_ip_address:
        logger.warning("Waiting for IP to be available")
        time.sleep(5)
        instance.reload()

    while True:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        if sock.connect_ex((instance.public_ip_address, 22)) == 0:
            break
        else:
            logger.warning("Waiting for SSH to be available")
            time.sleep(10)

    return instance.public_ip_address

def resize_filesystem(instance_id):
    ec2logger = EC2InstanceConnectLogger(debug=False)
    temp_key = EC2InstanceConnectKey(ec2logger.get_logger())
    ec2ic = boto3.client("ec2-instance-connect", region_name="ap-southeast-1")
    response = ec2ic.send_ssh_public_key(
        InstanceId=instance_id,
        InstanceOSUser="ubuntu",
        SSHPublicKey=temp_key.get_pub_key(),
    )
    assert response["Success"]

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
    logger.info(f"Created new AMI: {new_ami_id} with name: {new_ami_name}")
    return new_ami_id, new_ami_name

def wait_for_ami_available(ami_id):
    waiter = ec2_client.get_waiter('image_available')
    waiter.wait(ImageIds=[ami_id])
    logger.info(f"AMI {ami_id} is now available")

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
    logger.info(f"Modified block device mapping for AMI {ami_id}")

def terminate_instance(instance_id):
    ec2_resource.Instance(instance_id).terminate()
    logger.info(f"Terminated instance {instance_id}")

def main():
    try:
        instance_id = launch_temporary_instance()
        public_ip = wait_for_instance_running(instance_id)
        resize_filesystem(instance_id)
        new_ami_id, new_ami_name = create_new_ami(instance_id)
        wait_for_ami_available(new_ami_id)
        modify_ami_block_device_mapping(new_ami_id)
    finally:
        if 'instance_id' in locals():
            terminate_instance(instance_id)

    with open(os.environ['GITHUB_OUTPUT'], 'a') as fh:
        print(f'NEW_AMI_ID={new_ami_id}', file=fh)
        print(f'NEW_AMI_NAME={new_ami_name}', file=fh)

if __name__ == "__main__":
    main()