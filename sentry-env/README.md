# sentry-env

Boot-time Sentry environment variable injection for EC2 instances.
Injects `SENTRY_RELEASE`, `SENTRY_ENVIRONMENT`, `SENTRY_DSN`, and
`SENTRY_SERVER_NAME` into systemd services (specifically PostgreSQL).

The DSN is written only to `/run/sentry.env`. This file is a tmpfs path that lives
in RAM, is never written to disk, and is gone after reboot.

## File layout

````
sentry-env/
├── install.sh                 # Installer (run as root)
├── fetch-sentry-env.sh        # Boot-time fetcher script
├── sentry-env.service         # systemd oneshot unit
├── postgresql-sentry.conf     # systemd drop-in for postgresql.service
└── README.md
````

## How it works

1. `sentry-env.service` runs `fetch-sentry-env.sh` as a oneshot after `network-online.target`.
2. The script fetches AMI ID, instance ID, and region via **IMDSv2** (retries up to 3×, token fetched once and reused).
3. It reads the `Environment` EC2 instance tag to set `SENTRY_ENVIRONMENT` (falls back to `"production"`).
4. It fetches `SENTRY_DSN` from SSM Parameter Store at `/sentry/dsn` (SecureString, decrypted). If SSM is unreachable, it logs a warning and continues with an empty DSN.
5. `/run/sentry.env` is written (mode 0600, tmpfs — never on disk) in `KEY="VALUE"` format for systemd `EnvironmentFile=`.
6. The PostgreSQL drop-in (`postgresql-sentry.conf`) makes PostgreSQL wait for `sentry-env.service` and loads `/run/sentry.env` into its environment.

## Installation

````bash
sudo ./install.sh
# Override PostgreSQL service name (e.g. Ubuntu versioned cluster):
sudo ./install.sh postgresql@15-main
````

The installer prints the required IAM policy JSON on completion.

## Required IAM permissions

````json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SentryDSNFromSSM",
      "Effect": "Allow",
      "Action": "ssm:GetParameter",
      "Resource": "arn:aws:ssm:*:*:parameter/sentry/dsn"
    },
    {
      "Sid": "SentryEnvironmentTagLookup",
      "Effect": "Allow",
      "Action": "ec2:DescribeTags",
      "Resource": "*"
    }
  ]
}
````

`ec2:DescribeTags` is only needed for the `Environment` tag override. Remove it if you always use `SENTRY_ENVIRONMENT=production`.

## SSM setup

Store the DSN as a SecureString:

````bash
aws ssm put-parameter \
  --name /sentry/dsn \
  --value "https://yourkey@o123.ingest.sentry.io/456" \
  --type SecureString \
  --region us-east-1
````

## Testing

````bash
# Manual run (requires IMDS + AWS credentials):
sudo /usr/local/bin/fetch-sentry-env.sh

# Inspect the result (root only — 0600):
sudo cat /run/sentry.env

# Via systemd:
sudo systemctl start sentry-env.service
sudo journalctl -u sentry-env.service -n 50
````

## Notes

- `/run/sentry.env` is written atomically (tmpfs temp file + rename), mode 0600 (root only). It lives in RAM only. Never on disk, gone after reboot.
- The DSN does not appear in any persistent file, login shell environment, or disk snapshot.
- PostgreSQL does not natively report to Sentry. These env vars are available to background workers, `pg_cron` jobs, or sidecars with Sentry SDK integration.
- The script is idempotent. They are safe to re-run on every boot or after AMI bake.
- Supported on Ubuntu 22.04/24.04 and Amazon Linux 2023. Requires AWS CLI v2.
