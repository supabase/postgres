Packer & Ansible template that sets up a Digital Ocean snapshot of a PostgreSQL server with pre-installed and enabled goodies.

## Supported Images
- Ubuntu 18.04 Bionic (LTS)

## Default Features
✅ Postgres 12

✅ `wal_level` = `logical`

✅ `pgcrypto` enabled

✅ `pg_stat_statements` enabled

✅ `postgis` enabled


## Requirements
🗹 [Packer](https://www.packer.io/intro/getting-started/install.html)

🗹 [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/index.html)

## Walkthrough

1. Install the Ansible role `ANXS.postgresql`.
```
$ ansible-galaxy install ANXS.postgresql -r tasks/install_roles.yml --force
```

2. `DO_TOKEN`, `SNAPSHOT_NAME` and `REGION` all need to be defined. A list of valid Digital Ocean regions can be found [here](https://www.digitalocean.com/docs/platform/availability-matrix/).
```
$ export DO_TOKEN=your_digital_ocean_token
$ export SNAPSHOT_NAME=your_snapshot_name
$ export REGION=your_chosen_region
```

3. Create the Digital Ocean snapshot
```
$ packer build \
  -var "do_token=$DO_TOKEN" \
  -var "name=$SNAPSHOT_NAME" \
  -var "region=$REGION" \
  packer.json
```

Once this is complete, you now have a snapshot available to use for any of your droplets.

## Notes on provisioning
1. The PostgreSQL server can be further customised. Available provisioning variables that can be manipulated are found in `ansible/vars.yml`
2. There are also additional provisioning variables from the role [anxs.postgres](https://github.com/ANXS/postgresql). The exhaustive list can be found [here](https://github.com/ANXS/postgresql/blob/master/defaults/main.yml).
3. To be in line with the standards of images found in the Digital Ocean Marketplace, scripts found in `scripts` are also ran to clean up the snapshot and make it compatible with the Marketplace. They are taken from [here](https://github.com/digitalocean/marketplace-partners/tree/master/scripts). More information on what these scripts achieve can be found [here](https://github.com/digitalocean/marketplace-partners/blob/master/getting-started.md).

## Roadmap
🗹 Template for setting up a snapshot on AWS.