Packer & Ansible template that sets up a Digital Ocean snapshot of a PostgreSQL server with pre-installed and enabled goodies

## Specifications
- Ubuntu 18.04 (Bionic)

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
```
$ ansible-galaxy install ANXS.postgresql -r install_roles.yml --force

$ export DO_TOKEN=your_digital_ocean_token
$ export SNAPSHOT_NAME=your_snapshot_name
$ export REGION=your_chosen_region

# Name is now also mandatory
$ packer build \
  -var "do_token=$DO_TOKEN" \
  -var "name=$SNAPSHOT_NAME" \
  -var "$REGION" \
  packer.json
```
A list of available Digital Ocean regions can be found [here](https://www.digitalocean.com/docs/platform/availability-matrix/).

See [how to use ansible to update an existing instance](ansible/README.md).

## Notes on provisioning

1. Variables can be manipulated in `ansible/vars.yml`
2. The playbook uses the role [anxs.postgres](https://github.com/ANXS/postgresql). Other available variables can be found [here](https://github.com/ANXS/postgresql/blob/master/defaults/main.yml)
