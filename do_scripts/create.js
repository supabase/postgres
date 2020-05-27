const DigitalOcean = require("do-wrapper").default;
const fs = require("fs");
const YAML = require("yamljs");

const volumeName = "example"

const buildYamlPostgresUserData = async () => {
  const userData = {
    write_files: [
      // {
      //   path: '/etc/postgresql/12/main/postgresql.conf',
      //   encoding: 'b64',
      //   content: Buffer.from(buildPostgresConfig()).toString('base64'),
      // },
      {
        path: "/etc/postgresql.schema.sql",
        encoding: "b64",
        content: Buffer.from(buildPostgresSchema()).toString("base64"),
      },
    ],
    runcmd: [
      'sudo echo "host    all             all             0.0.0.0/0               md5" >> /etc/postgresql/12/main/pg_hba.conf',
      "systemctl enable --now postgresql",
      "sudo systemctl stop postgresql",
      `sudo rsync -av /var/lib/postgresql /mnt/${volumeName}`,
      `echo "data_directory = '/mnt/${volumeName}/postgresql/12/main'" >> /etc/postgresql/12/main/postgresql.conf`,
      "sudo systemctl start postgresql",
      "sudo rm -rf /var/lib/postgresql/12/main",
      "sudo -u postgres psql postgres < /etc/postgresql.schema.sql",
      "sudo systemctl restart system-postgresql.slice",
    ],
  };

  return YAML.stringify(userData);
};

const buildPostgresSchema = () => {
  userPassword = "postgres";
  return (
    fs.readFileSync("./initial-schema.sql", "utf8") +
    `\nALTER USER postgres WITH PASSWORD '${userPassword}';`
  );
};

const createNewDroplet = async () => {
  var api = new DigitalOcean(process.env.DO_TOKEN, 10);

  if (process.argv.length !== 4) {
    console.log("node info.js SNAPSHOT_ID SSH_KEY_ID");
    return 1;
  }
  const snapshot_id = process.argv[2];
  const ssh_key_id = process.argv[3];

  const user_data =
    "#cloud-config\n" + (await buildYamlPostgresUserData()).toString("utf8");

  api
    .volumesCreate({
      size_gigabytes: 10,
      name: `${volumeName}`,
      region: "sgp1",
      filesystem_type: "ext4",
    })
    .then((data) => {
      console.log(data.body);
      api
        .dropletsCreate({
          name: "example-droplet",
          region: "sgp1",
          size: "s-1vcpu-1gb",
          image: snapshot_id,
          ssh_keys: ssh_key_id,
          backups: false,
          ipv6: true,
          user_data: user_data,
          private_networking: null,
          volumes: [data.body.volume.id],
        })
        .then((data) => {
          console.log(data.body);
        })
        .catch((error) => {
          console.log(error);
        });
    })
    .catch((error) => {
      console.log(error);
    });
};

createNewDroplet()
