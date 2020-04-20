Calling ansible directly to update an existing running instance.

You first need to create an inventory file with the hosts you want to update, and connections settings.
Let's call the file `inventory_digitalocean`

```
DROPLET_IP_ADDRESS ansible_user=root
```

Then we can run the ansible playbook and override versions defined in the playbook.yml

```
ansible-playbook -i inventory_digitalocean \
  --private-key YOUR_SSH_PRIVATE_KEY \
  --extra-vars "restart_services=true postgrest_release=v7.0.0 postgrest_release_checksum=sha1:033aafb439792e9580d468baf6ce5d937a62797d" \
  ansible/playbook.yml
```

This would run the playbook with the versions defined in the `var` section of the playbook, and just
override the postgrest installation. *Note:* we set the `restart_services` variable to true, as we
need to restart services for the new versions to be picked up.

