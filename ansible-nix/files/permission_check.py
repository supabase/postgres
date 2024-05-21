import subprocess
import json
import sys

# Expected groups for each user
expected_results = {
    "postgres": [
        {"groupname": "postgres", "username": "postgres"},
        {"groupname": "ssl-cert", "username": "postgres"}
    ],
    "ubuntu": [
        {"groupname":"ubuntu","username":"ubuntu"},
        {"groupname":"adm","username":"ubuntu"},
        {"groupname":"dialout","username":"ubuntu"},
        {"groupname":"cdrom","username":"ubuntu"},
        {"groupname":"floppy","username":"ubuntu"},
        {"groupname":"sudo","username":"ubuntu"},
        {"groupname":"audio","username":"ubuntu"},
        {"groupname":"dip","username":"ubuntu"},
        {"groupname":"video","username":"ubuntu"},
        {"groupname":"plugdev","username":"ubuntu"},
        {"groupname":"lxd","username":"ubuntu"},
        {"groupname":"netdev","username":"ubuntu"}
    ],
    "root": [
        {"groupname":"root","username":"root"}
    ],
    "daemon": [
        {"groupname":"daemon","username":"daemon"}
    ],
    "bin": [
        {"groupname":"bin","username":"bin"}
    ],
    "sys": [
        {"groupname":"sys","username":"sys"}
    ],
    "sync": [
        {"groupname":"nogroup","username":"sync"}
    ],
    "games": [
        {"groupname":"games","username":"games"}
    ],
    "man": [
        {"groupname":"man","username":"man"}
    ],
    "lp": [
        {"groupname":"lp","username":"lp"}
    ],
    "mail": [
        {"groupname":"mail","username":"mail"}
    ],
    "news": [
        {"groupname":"news","username":"news"}
    ],
    "uucp": [
        {"groupname":"uucp","username":"uucp"}
    ],
    "proxy": [
        {"groupname":"proxy","username":"proxy"}
    ],
    "www-data": [
        {"groupname":"www-data","username":"www-data"}
    ],
    "backup": [
        {"groupname":"backup","username":"backup"}
    ],
    "list": [
        {"groupname":"list","username":"list"}
    ],
    "irc": [
        {"groupname":"irc","username":"irc"}
    ],
    "gnats": [
        {"groupname":"gnats","username":"gnats"}
    ],
    "nobody": [
        {"groupname":"nogroup","username":"nobody"}
    ],
    "systemd-network": [
        {"groupname":"systemd-network","username":"systemd-network"}
    ],
    "systemd-resolve": [
        {"groupname":"systemd-resolve","username":"systemd-resolve"}
    ],
    "systemd-timesync": [
        {"groupname":"systemd-timesync","username":"systemd-timesync"}
    ],
    "messagebus": [
        {"groupname":"messagebus","username":"messagebus"}
    ],
    "ec2-instance-connect": [
        {"groupname":"nogroup","username":"ec2-instance-connect"}
    ],
    "sshd": [
        {"groupname":"nogroup","username":"sshd"}
    ],
    "wal-g": [
        {"groupname":"wal-g","username":"wal-g"},
        {"groupname":"postgres","username":"wal-g"}
    ],
    "pgbouncer": [
        {"groupname":"pgbouncer","username":"pgbouncer"},
        {"groupname":"ssl-cert","username":"pgbouncer"},
        {"groupname":"postgres","username":"pgbouncer"}
    ],
    "gotrue": [
        {"groupname":"gotrue","username":"gotrue"}
    ],
    "envoy": [
        {"groupname":"envoy","username":"envoy"}
    ],
    "kong": [
        {"groupname":"kong","username":"kong"}
    ],
    "nginx": [
        {"groupname":"nginx","username":"nginx"}
    ],
    "vector": [
        {"groupname":"vector","username":"vector"},
        {"groupname":"adm","username":"vector"},
        {"groupname":"systemd-journal","username":"vector"},
        {"groupname":"postgres","username":"vector"}
    ],
    "adminapi": [
        {"groupname":"adminapi","username":"adminapi"},
        {"groupname":"root","username":"adminapi"},
        {"groupname":"systemd-journal","username":"adminapi"},
        {"groupname":"admin","username":"adminapi"},
        {"groupname":"postgres","username":"adminapi"},
        {"groupname":"pgbouncer","username":"adminapi"},
        {"groupname":"wal-g","username":"adminapi"},
        {"groupname":"postgrest","username":"adminapi"},
        {"groupname":"envoy","username":"adminapi"},
        {"groupname":"kong","username":"adminapi"},
        {"groupname":"vector","username":"adminapi"}
    ],
    "postgrest": [
        {"groupname":"postgrest","username":"postgrest"}
    ],
    "tcpdump": [
        {"groupname":"tcpdump","username":"tcpdump"}
    ],
    "systemd-coredump": [
        {"groupname":"systemd-coredump","username":"systemd-coredump"}
    ]
}
# This program depends on osquery being installed on the system
# Function to run osquery
def run_osquery(query):
    process = subprocess.Popen(['osqueryi', '--json', query], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output, error = process.communicate()
    return output.decode('utf-8')

def parse_json(json_str):
    try:
        return json.loads(json_str)
    except json.JSONDecodeError as e:
        print("Error decoding JSON:", e)
        sys.exit(1)

def compare_results(username, query_result):
    expected_result = expected_results.get(username)
    if expected_result is None:
        print(f"No expected result defined for user '{username}'")
        sys.exit(1)

    if query_result == expected_result:
        print(f"The query result for user '{username}' matches the expected result.")
    else:
        print(f"The query result for user '{username}' does not match the expected result.")
        print("Expected:", expected_result)
        print("Got:", query_result)
        sys.exit(1)

# Define usernames for which you want to compare results
usernames = ["postgres", "ubuntu", "root", "daemon", "bin", "sys", "sync", "games","man","lp","mail","news","uucp","proxy","www-data","backup","list","irc","gnats","nobody","systemd-network","systemd-resolve","systemd-timesync","messagebus","ec2-instance-connect","sshd","wal-g","pgbouncer","gotrue","envoy","kong","nginx","vector","adminapi","postgrest","tcpdump","systemd-coredump"]

# Iterate over usernames, run the query, and compare results
for username in usernames:
    query = f"SELECT u.username, g.groupname FROM users u JOIN user_groups ug ON u.uid = ug.uid JOIN groups g ON ug.gid = g.gid WHERE u.username = '{username}';"
    query_result = run_osquery(query)
    parsed_result = parse_json(query_result)
    compare_results(username, parsed_result)
