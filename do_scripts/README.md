# Creating a droplet with a volume attached to it
```
$ npm install
$ DO_TOKEN=insert_do_token node create.js insert_snapshot_id insert_ssh_key_id
```

# What was done
1. Create a volume with a unique name of our choosing. This determines the name of the directory of where the volume will reside in the droplet.
2. This is currently defined in the varialbe `volumeName`.
3. Using the ID generated, create a new droplet and attach the newly created volume.
4. Volume is already automatically mounted on to the droplet during this process.
5. Using the `user_data` parameter of creating a new droplet, inject shell commands that would transfer the data directory of the Postgres server to the attached volume.

# Tests
## Verifying if the volume is mounted
```
$ if grep -qs '/mnt/${volumeName} ' /proc/mounts; then
>     echo "It's mounted."
> else
>     echo "It's not mounted."
> fi
```
Running this should return `It's mounted`.

## Verifying the new data directory path
In SQL:
```
SHOW data_directory;
```
Running this should return the path `/mnt/example/postgresql/12/main`.

## Verifying data integrity
Right now, unique data written so far would be the presence of the role `public_readonly`. In SQL:
```
SELECT * FROM pg_roles;
```
Running this should return a list of roles including the role `public_readonly`.

