package aws

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	"github.com/aws/aws-sdk-go-v2/service/ssm/types"
)

// SSMClient wraps AWS SSM operations
type SSMClient struct {
	client *ssm.Client
	region string
}

// NewSSMClient creates a new SSM client
func NewSSMClient(ctx context.Context, region string) (*SSMClient, error) {
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	if err != nil {
		return nil, fmt.Errorf("failed to load AWS config: %w", err)
	}

	return &SSMClient{
		client: ssm.NewFromConfig(cfg),
		region: region,
	}, nil
}

// BuildSSMCommand creates a shell command string
func BuildSSMCommand(script string) string {
	return script
}

// WaitForSSMReady waits for SSM agent to be ready on the instance
func (c *SSMClient) WaitForSSMReady(ctx context.Context, instanceID string) error {
	maxAttempts := 60
	for i := 0; i < maxAttempts; i++ {
		input := &ssm.DescribeInstanceInformationInput{
			Filters: []types.InstanceInformationStringFilter{
				{
					Key:    aws.String("InstanceIds"),
					Values: []string{instanceID},
				},
			},
		}

		result, err := c.client.DescribeInstanceInformation(ctx, input)
		if err == nil && len(result.InstanceInformationList) > 0 {
			status := result.InstanceInformationList[0].PingStatus
			if status == types.PingStatusOnline {
				return nil
			}
		}

		time.Sleep(5 * time.Second)
	}

	return fmt.Errorf("timeout waiting for SSM agent to be ready")
}

// SendCommand sends a command to an instance via SSM
func (c *SSMClient) SendCommand(ctx context.Context, instanceID, command string) (string, error) {
	input := &ssm.SendCommandInput{
		InstanceIds:  []string{instanceID},
		DocumentName: aws.String("AWS-RunShellScript"),
		Parameters: map[string][]string{
			"commands": {command},
		},
	}

	result, err := c.client.SendCommand(ctx, input)
	if err != nil {
		return "", fmt.Errorf("failed to send command: %w", err)
	}

	return *result.Command.CommandId, nil
}

// WaitForCommandComplete waits for a command to complete
func (c *SSMClient) WaitForCommandComplete(ctx context.Context, commandID, instanceID string) error {
	maxAttempts := 600 // 50 minutes
	for i := 0; i < maxAttempts; i++ {
		input := &ssm.GetCommandInvocationInput{
			CommandId:  aws.String(commandID),
			InstanceId: aws.String(instanceID),
		}

		result, err := c.client.GetCommandInvocation(ctx, input)
		if err != nil {
			time.Sleep(5 * time.Second)
			continue
		}

		switch result.Status {
		case types.CommandInvocationStatusSuccess:
			return nil
		case types.CommandInvocationStatusFailed, types.CommandInvocationStatusCancelled, types.CommandInvocationStatusTimedOut:
			return fmt.Errorf("command failed with status: %s", result.Status)
		}

		time.Sleep(5 * time.Second)
	}

	return fmt.Errorf("timeout waiting for command to complete")
}

// StartSSHSession starts an interactive SSM session
func (c *SSMClient) StartSSHSession(ctx context.Context, instanceID string) error {
	cmd := exec.CommandContext(ctx, "aws", "ssm", "start-session",
		"--target", instanceID,
		"--region", c.region)

	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	return cmd.Run()
}

// BuildTarCommand creates a command to tar and base64 encode a file/directory
func BuildTarCommand(src string) string {
	// Get parent directory for mkdir
	dir := filepath.Dir(src)
	if dir == "." {
		dir = ""
	}

	mkdirPart := ""
	if dir != "" {
		mkdirPart = fmt.Sprintf("mkdir -p %s && ", dir)
	}

	return fmt.Sprintf("%star -czf - %s | base64", mkdirPart, src)
}

// BuildUntarCommand creates a command to base64 decode and untar
func BuildUntarCommand(dst string) string {
	return fmt.Sprintf("mkdir -p %s && base64 -d | tar -xzf - -C %s", dst, dst)
}

// BuildSyncFileCommand creates a command to sync a file to the instance
func BuildSyncFileCommand(dst, tarBase64Data string) string {
	parentDir := filepath.Dir(dst)
	return fmt.Sprintf("mkdir -p %s && echo '%s' | base64 -d | tar -xzf - -C /", parentDir, tarBase64Data)
}

// SyncFile syncs a local file/directory to the instance
func (c *SSMClient) SyncFile(ctx context.Context, instanceID, src, dst string) error {
	// Read and tar the source file/directory
	tarCmd := exec.Command("bash", "-c", BuildTarCommand(src))
	tarOutput, err := tarCmd.Output()
	if err != nil {
		return fmt.Errorf("failed to tar source: %w", err)
	}

	tarBase64 := string(tarOutput)

	// Build and send the untar command
	syncCmd := BuildSyncFileCommand(dst, tarBase64)
	commandID, err := c.SendCommand(ctx, instanceID, syncCmd)
	if err != nil {
		return fmt.Errorf("failed to send sync command: %w", err)
	}

	// Wait for command to complete
	if err := c.WaitForCommandComplete(ctx, commandID, instanceID); err != nil {
		return fmt.Errorf("sync command failed: %w", err)
	}

	return nil
}
