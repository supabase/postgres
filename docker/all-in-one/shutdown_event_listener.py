#!/usr/bin/python3

# This script is used to make sure the latest LSN checkpoint is persisted remotely
#  before the container is stopped. It is triggered by the shutdown event listener
#  or every 60 seconds, whichever comes first.
# The script will ship the latest LSN checkpoint to the remote storage if:
# - the latest LSN checkpoint is different from the previous, already shipped, one
# - the latest LSN checkpoint is not 0/0 as to avoid shipping empty checkpoints
# - the latest LSN checkpoint is not older than 10 minutes, thus reducing remote write calls

import os
import sys
import subprocess
import time

LSN_CHECKPOINT_SHIP_INTERVAL = 10

checkpointFile = '/data/latest-lsn-checkpoint'
checkpointFilePrevious = '/data/latest-lsn-checkpoint.previous'

def write_stdout(s):
    sys.stdout.write(s)
    sys.stdout.flush()

def write_stderr(s):
    sys.stderr.write(s)
    sys.stderr.flush()

def main():
    while 1:
        write_stdout('READY\n')

        line = sys.stdin.readline()
        write_stderr(line)

        # read event payload and print it to stderr
        headers = dict([ x.split(':') for x in line.split() ])
        data = sys.stdin.read(int(headers['len']))
        write_stderr(data)

        if headers['eventname'] == 'TICK_60':
            if os.path.getmtime(checkpointFile) < time.time() - 60 * LSN_CHECKPOINT_SHIP_INTERVAL:
                break

            previousLSN = ''
            with open(checkpointFilePrevious) as f:
                previousLSN = f.read()

            # If the current LSN is different from the previous one, persist it remotely
            with open(checkpointFile) as f:
                currentLSN = f.read()
                if currentLSN != '0/0' and currentLSN != previousLSN:
                    subprocess.run(["/usr/bin/admin-mgr", "lsn-checkpoint-push"])
                    with open(previousLSN, 'w') as f:
                        f.write(checkpointFilePrevious)

        write_stdout('RESULT 2\nOK')

if __name__ == '__main__':
    main()
