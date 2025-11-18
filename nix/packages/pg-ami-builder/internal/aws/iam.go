package aws

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/iam"
)

// IAMClient wraps AWS IAM operations
type IAMClient struct {
	client *iam.Client
}

// NewIAMClient creates a new IAM client
func NewIAMClient(ctx context.Context) (*IAMClient, error) {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to load AWS config: %w", err)
	}

	return &IAMClient{
		client: iam.NewFromConfig(cfg),
	}, nil
}

// EnsureInstanceProfile creates or retrieves an IAM instance profile for SSM access
func (c *IAMClient) EnsureInstanceProfile(ctx context.Context) (string, error) {
	roleName := "pg-ami-builder-ssm-role"
	profileName := "pg-ami-builder-ssm-profile"

	// Try to get existing role
	_, err := c.client.GetRole(ctx, &iam.GetRoleInput{
		RoleName: aws.String(roleName),
	})
	if err != nil {
		// Role doesn't exist, create it
		trustPolicy := `{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}`

		_, err = c.client.CreateRole(ctx, &iam.CreateRoleInput{
			RoleName:                 aws.String(roleName),
			AssumeRolePolicyDocument: aws.String(trustPolicy),
			Description:              aws.String("IAM role for pg-ami-builder instances to use SSM"),
		})
		if err != nil {
			return "", fmt.Errorf("failed to create IAM role: %w", err)
		}

		// Attach SSM managed policy
		_, err = c.client.AttachRolePolicy(ctx, &iam.AttachRolePolicyInput{
			RoleName:  aws.String(roleName),
			PolicyArn: aws.String("arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"),
		})
		if err != nil {
			return "", fmt.Errorf("failed to attach SSM policy: %w", err)
		}
	}

	// Try to get existing instance profile
	_, err = c.client.GetInstanceProfile(ctx, &iam.GetInstanceProfileInput{
		InstanceProfileName: aws.String(profileName),
	})
	if err != nil {
		// Instance profile doesn't exist, create it
		_, err = c.client.CreateInstanceProfile(ctx, &iam.CreateInstanceProfileInput{
			InstanceProfileName: aws.String(profileName),
		})
		if err != nil {
			return "", fmt.Errorf("failed to create instance profile: %w", err)
		}

		// Add role to instance profile
		_, err = c.client.AddRoleToInstanceProfile(ctx, &iam.AddRoleToInstanceProfileInput{
			InstanceProfileName: aws.String(profileName),
			RoleName:            aws.String(roleName),
		})
		if err != nil {
			return "", fmt.Errorf("failed to add role to instance profile: %w", err)
		}
	}

	return profileName, nil
}
