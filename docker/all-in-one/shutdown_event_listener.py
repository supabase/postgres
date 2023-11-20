#!/usr/bin/python3
import sys
import subprocess

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
                        f.write(currentLSN)

        write_stdout('RESULT 2\nOK')

if __name__ == '__main__':
    main()