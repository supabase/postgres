# Supabase Postgres 

Unmodified Postgres with some opinionated defaults and plugins.

Packer & Ansible templates that sets up a PostgreSQL server with pre-installed and enabled goodies in either of the following providers:
- AWS (AMIs)
- Digital Ocean (Snapshots)

## Supported Images
- Ubuntu 18.04 Bionic (LTS)

## Default Features
✅ Postgres 12

✅ `wal_level` = `logical`

✅ `pgcrypto` enabled

✅ `pg_stat_statements` enabled

✅ `postgis` enabled

✅ `pgTAP` enabled

## Requirements
🗹 [Packer](https://www.packer.io/intro/getting-started/install.html)

🗹 [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/index.html)

## Walkthrough

### Install the Ansible role `ANXS.postgresql`.
```
$ ansible-galaxy install ANXS.postgresql -r tasks/install_roles.yml --force
```

### For **Digital Ocean**
- `DO_TOKEN`, `SNAPSHOT_NAME` and `REGION` all need to be defined. A list of valid Digital Ocean regions can be found [here](https://www.digitalocean.com/docs/platform/availability-matrix/).
```
$ export DO_TOKEN=your_digital_ocean_token
$ export SNAPSHOT_NAME=your_snapshot_name
$ export REGION=your_chosen_region
```

- Create the Digital Ocean snapshot
```
$ packer build \
  -var "do_token=$DO_TOKEN" \
  -var "name=$SNAPSHOT_NAME" \
  -var "region=$REGION" \
  digitalOcean.json
```

### For **AWS**
- `AWS_ACCESS_KEY`, `AWS_SECRET_KEY`, `SNAPSHOT_NAME` and `REGION` all need to be defined. A list of valid AWS regions can be found [here](https://docs.aws.amazon.com/general/latest/gr/ec2-service.html).
```
$ export AWS_ACCESS_KEY=your_aws_access_key
$ export AWS_SECRET_KEY=your_aws_secret_key
$ export SNAPSHOT_NAME=your_snapshot_name
$ export REGION=your_chosen_region
```

- Create the AWS AMI
```
$ packer build \
  -var "aws_access_key=$AWS_ACCESS_KEY" \
  -var "aws_secret_key=$AWS_SECRET_KEY" \
  -var "name=$SNAPSHOT_NAME" \
  -var "region=$REGION" \
  amazon.json
```

Once this is complete, you now have a snapshot or AMI available to use for any of your droplets or EC2 instances respectively.

## Notes on provisioning
1. The PostgreSQL server can be further customised. Available provisioning variables that can be manipulated are found in `ansible/vars.yml`
2. There are also additional provisioning variables from the role [anxs.postgres](https://github.com/ANXS/postgresql). The exhaustive list can be found [here](https://github.com/ANXS/postgresql/blob/master/defaults/main.yml).
3. To be in line with the standards of images found in the Digital Ocean Marketplace, scripts found in `scripts` are also ran to clean up the snapshot and make it compatible with the Marketplace. They are taken from [here](https://github.com/digitalocean/marketplace-partners/tree/master/scripts). More information on what these scripts achieve can be found [here](https://github.com/digitalocean/marketplace-partners/blob/master/getting-started.md).

## Roadmap
🗹 tbc
