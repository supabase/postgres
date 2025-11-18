package aws

import (
	"context"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ec2/types"
)

// EC2Client wraps AWS EC2 operations
type EC2Client struct {
	client *ec2.Client
	region string
}

// NewEC2Client creates a new EC2 client
func NewEC2Client(ctx context.Context, region string) (*EC2Client, error) {
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	if err != nil {
		return nil, fmt.Errorf("failed to load AWS config: %w", err)
	}

	return &EC2Client{
		client: ec2.NewFromConfig(cfg),
		region: region,
	}, nil
}

// GenerateExecutionID creates a unique execution ID
func GenerateExecutionID(postgresVersion string) string {
	timestamp := time.Now().Unix()
	return fmt.Sprintf("%d-%s", timestamp, postgresVersion)
}

// BuildInstanceTags creates EC2 tags for the instance
func BuildInstanceTags(executionID, phase string) []types.Tag {
	return []types.Tag{
		{Key: aws.String("creator"), Value: aws.String("pg-ami-builder")},
		{Key: aws.String("packerExecutionId"), Value: aws.String(executionID)},
		{Key: aws.String("appType"), Value: aws.String("postgres")},
		{Key: aws.String("phase"), Value: aws.String(phase)},
		{Key: aws.String("managedBy"), Value: aws.String("pg-ami-builder")},
	}
}

// LaunchInstanceInput contains parameters for launching an instance
type LaunchInstanceInput struct {
	AMI             string
	InstanceType    string
	ExecutionID     string
	Phase           string
	InstanceProfile string
}

// LaunchInstance launches an EC2 instance
func (c *EC2Client) LaunchInstance(ctx context.Context, input *LaunchInstanceInput) (string, error) {
	// Get or create security group
	sgID, err := c.ensureSecurityGroup(ctx)
	if err != nil {
		return "", fmt.Errorf("failed to ensure security group: %w", err)
	}

	// Build tag specifications
	tags := BuildInstanceTags(input.ExecutionID, input.Phase)
	tagSpec := types.TagSpecification{
		ResourceType: types.ResourceTypeInstance,
		Tags:         tags,
	}

	runInput := &ec2.RunInstancesInput{
		ImageId:           aws.String(input.AMI),
		InstanceType:      types.InstanceType(input.InstanceType),
		MinCount:          aws.Int32(1),
		MaxCount:          aws.Int32(1),
		SecurityGroupIds:  []string{sgID},
		TagSpecifications: []types.TagSpecification{tagSpec},
	}

	// Add IAM instance profile if provided
	if input.InstanceProfile != "" {
		runInput.IamInstanceProfile = &types.IamInstanceProfileSpecification{
			Name: aws.String(input.InstanceProfile),
		}
	}

	result, err := c.client.RunInstances(ctx, runInput)
	if err != nil {
		return "", fmt.Errorf("failed to launch instance: %w", err)
	}

	if len(result.Instances) == 0 {
		return "", fmt.Errorf("no instances were launched")
	}

	return *result.Instances[0].InstanceId, nil
}

// ensureSecurityGroup creates or retrieves the security group
func (c *EC2Client) ensureSecurityGroup(ctx context.Context) (string, error) {
	groupName := "pg-ami-builder-sg"

	// Try to find existing group
	describeInput := &ec2.DescribeSecurityGroupsInput{
		Filters: []types.Filter{
			{
				Name:   aws.String("group-name"),
				Values: []string{groupName},
			},
		},
	}

	result, err := c.client.DescribeSecurityGroups(ctx, describeInput)
	if err == nil && len(result.SecurityGroups) > 0 {
		return *result.SecurityGroups[0].GroupId, nil
	}

	// Create new security group
	createInput := &ec2.CreateSecurityGroupInput{
		GroupName:   aws.String(groupName),
		Description: aws.String("Security group for pg-ami-builder instances"),
	}

	createResult, err := c.client.CreateSecurityGroup(ctx, createInput)
	if err != nil {
		return "", fmt.Errorf("failed to create security group: %w", err)
	}

	return *createResult.GroupId, nil
}

// WaitForInstanceRunning waits for an instance to be in running state
func (c *EC2Client) WaitForInstanceRunning(ctx context.Context, instanceID string) error {
	waiter := ec2.NewInstanceRunningWaiter(c.client)
	maxWaitTime := 10 * time.Minute

	return waiter.Wait(ctx, &ec2.DescribeInstancesInput{
		InstanceIds: []string{instanceID},
	}, maxWaitTime)
}

// TerminateInstance terminates an EC2 instance
func (c *EC2Client) TerminateInstance(ctx context.Context, instanceID string) error {
	_, err := c.client.TerminateInstances(ctx, &ec2.TerminateInstancesInput{
		InstanceIds: []string{instanceID},
	})
	if err != nil {
		return fmt.Errorf("failed to terminate instance: %w", err)
	}
	return nil
}

// BuildAMIName creates a name for the AMI
func BuildAMIName(phase, executionID string) string {
	return fmt.Sprintf("pg-ami-builder-%s-%s", phase, executionID)
}

// BuildAMITags creates tags for the AMI
func BuildAMITags(executionID, phase, postgresVersion, gitSHA string) []types.Tag {
	tags := []types.Tag{
		{Key: aws.String("creator"), Value: aws.String("pg-ami-builder")},
		{Key: aws.String("packerExecutionId"), Value: aws.String(executionID)},
		{Key: aws.String("phase"), Value: aws.String(phase)},
		{Key: aws.String("postgresVersion"), Value: aws.String(postgresVersion)},
		{Key: aws.String("managedBy"), Value: aws.String("pg-ami-builder")},
	}

	if gitSHA != "" {
		tags = append(tags, types.Tag{
			Key:   aws.String("gitSHA"),
			Value: aws.String(gitSHA),
		})
	}

	return tags
}

// CreateAMIInput contains parameters for creating an AMI
type CreateAMIInput struct {
	InstanceID      string
	ExecutionID     string
	Phase           string
	PostgresVersion string
	GitSHA          string
}

// CreateAMI creates an AMI from an instance
func (c *EC2Client) CreateAMI(ctx context.Context, input *CreateAMIInput) (string, error) {
	amiName := BuildAMIName(input.Phase, input.ExecutionID)
	tags := BuildAMITags(input.ExecutionID, input.Phase, input.PostgresVersion, input.GitSHA)

	// Create the AMI
	createInput := &ec2.CreateImageInput{
		InstanceId:  aws.String(input.InstanceID),
		Name:        aws.String(amiName),
		Description: aws.String(fmt.Sprintf("PostgreSQL %s AMI - %s", input.PostgresVersion, input.Phase)),
		TagSpecifications: []types.TagSpecification{
			{
				ResourceType: types.ResourceTypeImage,
				Tags:         tags,
			},
		},
	}

	result, err := c.client.CreateImage(ctx, createInput)
	if err != nil {
		return "", fmt.Errorf("failed to create AMI: %w", err)
	}

	return *result.ImageId, nil
}

// WaitForAMIAvailable waits for an AMI to be available
func (c *EC2Client) WaitForAMIAvailable(ctx context.Context, amiID string) error {
	waiter := ec2.NewImageAvailableWaiter(c.client)
	maxWaitTime := 20 * time.Minute

	return waiter.Wait(ctx, &ec2.DescribeImagesInput{
		ImageIds: []string{amiID},
	}, maxWaitTime)
}

// FindInstanceByTag finds an instance by a specific tag key-value pair
func (c *EC2Client) FindInstanceByTag(ctx context.Context, tagKey string, tagValue string) (string, error) {
	input := &ec2.DescribeInstancesInput{
		Filters: []types.Filter{
			{
				Name:   aws.String(fmt.Sprintf("tag:%s", tagKey)),
				Values: []string{tagValue},
			},
			{
				Name:   aws.String("instance-state-name"),
				Values: []string{"pending", "running", "stopping", "stopped"},
			},
		},
	}

	result, err := c.client.DescribeInstances(ctx, input)
	if err != nil {
		return "", fmt.Errorf("failed to describe instances: %w", err)
	}

	// Find the most recent instance
	var instanceID string
	for _, reservation := range result.Reservations {
		for _, instance := range reservation.Instances {
			if instance.InstanceId != nil {
				instanceID = *instance.InstanceId
				break
			}
		}
		if instanceID != "" {
			break
		}
	}

	if instanceID == "" {
		return "", fmt.Errorf("no instance found with tag %s=%s", tagKey, tagValue)
	}

	return instanceID, nil
}

// FindLatestAMI finds the latest AMI matching the given filters
// This mimics packer's source_ami_filter behavior for Ubuntu 24.04 ARM64
func (c *EC2Client) FindLatestAMI(ctx context.Context, namePattern string, owner string) (string, error) {
	input := &ec2.DescribeImagesInput{
		Filters: []types.Filter{
			{
				Name:   aws.String("name"),
				Values: []string{namePattern},
			},
			{
				Name:   aws.String("state"),
				Values: []string{"available"},
			},
			{
				Name:   aws.String("virtualization-type"),
				Values: []string{"hvm"},
			},
			{
				Name:   aws.String("root-device-type"),
				Values: []string{"ebs"},
			},
		},
		Owners: []string{owner},
	}

	result, err := c.client.DescribeImages(ctx, input)
	if err != nil {
		return "", fmt.Errorf("failed to describe images: %w", err)
	}

	if len(result.Images) == 0 {
		return "", fmt.Errorf("no AMI found matching pattern %q from owner %q", namePattern, owner)
	}

	// Find the most recent image by CreationDate
	var latest *types.Image
	for i := range result.Images {
		img := &result.Images[i]
		if latest == nil || (img.CreationDate != nil && latest.CreationDate != nil && *img.CreationDate > *latest.CreationDate) {
			latest = img
		}
	}

	if latest == nil || latest.ImageId == nil {
		return "", fmt.Errorf("no valid AMI found")
	}

	return *latest.ImageId, nil
}

// FindAMIByTag finds an AMI by a specific tag key-value pair
func (c *EC2Client) FindAMIByTag(ctx context.Context, tagKey string, tagValue string) (string, error) {
	input := &ec2.DescribeImagesInput{
		Filters: []types.Filter{
			{
				Name:   aws.String(fmt.Sprintf("tag:%s", tagKey)),
				Values: []string{tagValue},
			},
		},
		Owners: []string{"self"},
	}

	result, err := c.client.DescribeImages(ctx, input)
	if err != nil {
		return "", fmt.Errorf("failed to describe images: %w", err)
	}

	if len(result.Images) == 0 {
		return "", fmt.Errorf("no AMI found with tag %s=%s", tagKey, tagValue)
	}

	// Return the most recent one if multiple exist
	var latest *types.Image
	for i := range result.Images {
		img := &result.Images[i]
		if latest == nil || (img.CreationDate != nil && latest.CreationDate != nil && *img.CreationDate > *latest.CreationDate) {
			latest = img
		}
	}

	if latest == nil || latest.ImageId == nil {
		return "", fmt.Errorf("no valid AMI found")
	}

	return *latest.ImageId, nil
}
