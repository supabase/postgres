# PR AMI Integration Testing Setup

This document describes the setup for running integration tests from the private `supabase/tests` repository against AMIs built from PRs in the `supabase/postgres` repository.

## Overview

The integration test workflow allows you to:
1. Build a test AMI from a PR branch
2. Trigger integration tests in the private `supabase/tests` repo with that AMI
3. Report test results back to the PR as a required status check
4. Gate PR merges on successful integration tests

## Architecture

```
┌─────────────────────────────────────────┐
│  supabase/postgres (PR to develop)      │
│                                         │
│  1. Label PR with "test-ami"            │
│  2. Build test AMI                      │
│  3. Create pending status check         │
│  4. Dispatch event to tests repo ────────┼────┐
└─────────────────────────────────────────┘    │
                                                │
                                                ▼
                                    ┌───────────────────────────┐
                                    │  supabase/tests (private) │
                                    │                           │
                                    │  5. Run integration tests │
                                    │  6. Report results back   │
                                    │  7. Clean up AMI          │
                                    └───────────────────────────┘
                                                │
                                                ▼
┌─────────────────────────────────────────┐
│  GitHub PR Status Checks                │
│                                         │
│  ✅ ami-integration-tests/pg15          │
│  ✅ ami-integration-tests/pg16          │
│  ✅ ami-integration-tests/pg17          │
└─────────────────────────────────────────┘
```

## Required Secrets

### In `supabase/postgres` repository:

1. **`TESTS_REPO_DISPATCH_PAT`** (required)
   - A GitHub Personal Access Token with `repo` scope
   - Used to trigger workflows in the private `supabase/tests` repo via `repository_dispatch`
   - Token should be created by a user with write access to `supabase/tests`
   - Add via: Settings → Secrets and variables → Actions → New repository secret

2. **`DEV_AWS_ROLE`** (already exists)
   - AWS IAM role for building and managing test AMIs
   - Used for AWS authentication via OIDC

### In `supabase/tests` repository:

1. **`POSTGRES_REPO_STATUS_PAT`** (required)
   - A GitHub Personal Access Token with `repo` scope
   - Used to update commit status checks on `supabase/postgres` PRs
   - Token should be created by a user with write access to `supabase/postgres`
   - Add via: Settings → Secrets and variables → Actions → New repository secret

2. **Other secrets** (already exist)
   - `AWS_DEV_ROLE` - AWS IAM role
   - `INFRA_INTEGRATION_STAGING_V0_KEY` - Platform API key
   - `INFRA_INTEGRATION_STAGING_V1_KEY` - Platform API key
   - `PLATFORM_THROTTLE_SKIP_TOKEN_STAGING` - API throttle bypass

## Workflow Files

### 1. `supabase/postgres/.github/workflows/pr-ami-test-trigger.yml`

**Purpose:** Build test AMI and trigger integration tests

**Triggers:**
- Pull request labeled with `test-ami`
- Pull request synchronized (new commits) when label is present

**What it does:**
1. Checks for `test-ami` label
2. Builds AMI for each PostgreSQL version (15, 16, 17)
3. Creates pending status check on PR
4. Dispatches event to `supabase/tests` with AMI details
5. Comments on PR with AMI information
6. Cleans up resources on completion/failure

### 2. `supabase/tests/.github/workflows/postgres_pr_ami_test.yml`

**Purpose:** Run integration tests and report results

**Triggers:**
- `repository_dispatch` event type: `postgres-ami-pr-test`

**What it does:**
1. Receives AMI details from dispatch payload
2. Creates Supabase project with specified Postgres version
3. Runs integration test suite:
   - Platform integration tests
   - Client library tests
   - Platform logs tests
4. Updates commit status on original PR
5. Comments on PR with test results
6. Cleans up test project and AMI

## Setup Instructions

### Step 1: Create GitHub Personal Access Tokens

#### Token 1: For `supabase/postgres` (TESTS_REPO_DISPATCH_PAT)
1. Go to GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. Generate new token with:
   - **Repository access:** Only select repositories → `supabase/tests`
   - **Permissions:**
     - Repository permissions → Actions: Read and write
     - Repository permissions → Contents: Read-only
3. Copy token and add to `supabase/postgres` secrets as `TESTS_REPO_DISPATCH_PAT`

#### Token 2: For `supabase/tests` (POSTGRES_REPO_STATUS_PAT)
1. Generate new token with:
   - **Repository access:** Only select repositories → `supabase/postgres`
   - **Permissions:**
     - Repository permissions → Commit statuses: Read and write
     - Repository permissions → Issues: Read and write (for PR comments)
     - Repository permissions → Pull requests: Read-only
2. Copy token and add to `supabase/tests` secrets as `POSTGRES_REPO_STATUS_PAT`

### Step 2: Deploy Workflow Files

1. **In `supabase/postgres` repository:**
   ```bash
   # Add and commit the workflow file
   git add .github/workflows/pr-ami-test-trigger.yml
   git commit -m "feat: add PR AMI integration test trigger workflow"
   git push
   ```

2. **In `supabase/tests` repository:**
   ```bash
   # Add and commit the workflow file
   git add .github/workflows/postgres_pr_ami_test.yml
   git commit -m "feat: add postgres PR AMI test receiver workflow"
   git push
   ```

### Step 3: Configure Branch Protection Rules

To require integration tests before merging to `develop`:

1. Go to `supabase/postgres` → Settings → Branches
2. Edit branch protection rule for `develop`
3. Enable "Require status checks to pass before merging"
4. Add required status checks:
   - `ami-integration-tests/pg15`
   - `ami-integration-tests/pg16`
   - `ami-integration-tests/pg17`
5. Save changes

## Usage

### Running Integration Tests on a PR

1. **Open or update a PR to `develop` branch**

2. **Add the `test-ami` label:**
   - Go to the PR page
   - Click "Labels" on the right sidebar
   - Add the `test-ami` label

3. **Wait for AMI build:**
   - The workflow will start automatically
   - Check the "Actions" tab for progress
   - AMI build takes ~45-60 minutes per PostgreSQL version

4. **Monitor test execution:**
   - Once AMI is built, tests will run in the private `supabase/tests` repo
   - PR status checks will update automatically
   - You'll see comments on the PR with progress and results

5. **Review results:**
   - ✅ Green check: Tests passed, PR can be merged
   - ❌ Red X: Tests failed, review the test logs
   - Click the "Details" link in status checks to view test output

### Manual Trigger (Optional)

You can also trigger tests manually via workflow_dispatch in the GitHub Actions UI.

## Troubleshooting

### Status check never completes
- Check if the workflow ran in `supabase/tests`
- Verify the `POSTGRES_REPO_STATUS_PAT` secret is valid
- Check Actions logs for authentication errors

### AMI build fails
- Check AWS credentials and role permissions
- Review the packer build logs in the workflow
- Verify all dependencies are available in the nix flake

### Tests fail unexpectedly
- Check if the staging environment is healthy
- Review test logs in the `supabase/tests` workflow
- Verify all required secrets are configured

### Permission errors
- Verify PAT tokens have correct scopes
- Check repository access permissions for the tokens
- Ensure tokens haven't expired

## Customization

### Running different test suites

Edit `supabase/tests/.github/workflows/postgres_pr_ami_test.yml` to:
- Add/remove test commands
- Change test environment (staging vs prod)
- Adjust timeout values
- Modify resource cleanup behavior

### Changing trigger conditions

Edit `supabase/postgres/.github/workflows/pr-ami-test-trigger.yml` to:
- Use different label names
- Trigger on different events
- Build for specific PostgreSQL versions only
- Use different AWS regions

### Test result notifications

The workflow already:
- Updates PR status checks
- Adds PR comments with results
- Links to detailed test logs

You can extend this to:
- Send Slack notifications
- Create GitHub issues for failures
- Update external dashboards

## Cost Considerations

- Each test run builds temporary AMIs and creates test projects
- AMIs are automatically cleaned up after tests
- Test projects are deleted after test completion
- Estimated cost: ~$1-2 per full test run (all PG versions)

## Maintenance

### Keeping workflows updated

- Review workflow files when updating PostgreSQL versions
- Update test suites as new features are added
- Monitor for deprecated GitHub Actions
- Rotate PAT tokens before expiration (typically 90 days)

### Monitoring

- Set up alerts for workflow failures
- Track test execution times
- Monitor resource usage and costs
- Review test coverage periodically

## Security

- PAT tokens are stored as encrypted secrets
- Workflows use OIDC for AWS authentication (no long-lived credentials)
- Test AMIs are isolated to development environment
- Automatic cleanup prevents resource leaks

## Support

For issues or questions:
- Check workflow logs in the Actions tab
- Review this documentation
- Contact the infrastructure team
- Open an issue in the relevant repository
