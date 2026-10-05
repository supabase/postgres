# shellcheck shell=bash

dir=$1
name=$2

for disk in root data; do
	qemu-img convert -O raw "$dir/$disk.qcow2" "$dir/$disk.raw"
done
root_snapshot=$(coldsnap upload --wait --omit-zero-blocks --no-progress "$dir/root.raw")
data_snapshot=$(coldsnap upload --wait --omit-zero-blocks --no-progress "$dir/data.raw")
ami_id=$(aws ec2 register-image \
	--name "$name" \
	--architecture arm64 \
	--boot-mode uefi \
	--ena-support \
	--virtualization-type hvm \
	--root-device-name /dev/xvda \
	--block-device-mappings \
	"DeviceName=/dev/xvda,Ebs={SnapshotId=$root_snapshot,VolumeSize=10,VolumeType=gp3,Iops=3000,Throughput=125,DeleteOnTermination=true}" \
	"DeviceName=/dev/xvdh,Ebs={SnapshotId=$data_snapshot,VolumeSize=1,VolumeType=gp3,DeleteOnTermination=true}" \
	--query ImageId --output text) || {
	aws ec2 delete-snapshot --snapshot-id "$root_snapshot"
	aws ec2 delete-snapshot --snapshot-id "$data_snapshot"
	exit 1
}
aws ec2 create-tags --resources "$ami_id" "$root_snapshot" "$data_snapshot" --tags \
	Key=creator,Value=packer \
	Key=appType,Value=postgres \
	"Key=postgresVersion,Value=$POSTGRES_VERSION" \
	"Key=sourceSha,Value=$SOURCE_SHA" \
	"Key=packerExecutionId,Value=$PACKER_EXECUTION_ID"
echo "ami: $ami_id"

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
	echo "stage2_ami_id=$ami_id" >>"$GITHUB_OUTPUT"
fi
