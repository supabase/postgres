#!/usr/bin/env bash

set -euo pipefail

# Summarizes the output of cleanup-stale-ami-build-resources.sh for one region as one tab-separated
# line: region, failed count, the number cleaned per resource type in the fixed order
#   testinfra instance, Packer instance, network interface, volume, security group, key pair, snapshot
# then the number of ghost executions and the number of executions still to clean, e.g.
#   "us-east-1<TAB>1<TAB>0<TAB>2<TAB>0<TAB>0<TAB>0<TAB>10<TAB>0<TAB>4<TAB>0".
# Resources are counted from the "Deleting ..." / "Terminating ..." log lines, minus any that a
# "Cleanup failed: ..." line says could not be deleted.
# A ghost execution is one whose cleanup completed with nothing to delete and no failure. Still to
# clean is the number of stale executions the job found minus the number it started on.
# A region whose log is missing or empty is reported as "region<TAB>n/a".
# ci/add-job-durations.sh appends the job duration and ci/build-slack-payload.sh renders the lines.

region=${1:-}
log=${2:-}
if [[ -z $region || -z $log ]]; then
	echo "Usage: $0 <region> <log-file>" >&2
	exit 2
fi

if [[ ! -s $log ]]; then
	printf '%s\tn/a\n' "$region"
	exit 0
fi

awk -v region="$region" '
function add(kind, n) { count[kind] += n }

# lines from the per-execution cleanup start with the execution id; sub() below rewrites $0
{ id = $1 }

/^[0-9]+ stale executions found/ { found = $1 }
/ Cleaning up AMI build resources for execution / { started[id] = 1 }
/ Packer cleanup complete[[:space:]]*$/ { complete[id] = 1 }
/Cleanup failed: / { failed++; failed_id[id] = 1 }

/Terminating testinfra instances: / { acted[id] = 1; sub(/.*instances: /, ""); add("testinfra instance", NF); next }
/Terminating Packer instances: / { acted[id] = 1; sub(/.*instances: /, ""); add("Packer instance", NF); next }
/Cleanup failed: unable to terminate testinfra instances: / { sub(/.*instances: /, ""); add("testinfra instance", -NF); next }
/Cleanup failed: unable to terminate Packer instances: / { sub(/.*instances: /, ""); add("Packer instance", -NF); next }

/Deleting network interface: / { acted[id] = 1; add("network interface", 1) }
/Cleanup failed: unable to delete network interface: / { add("network interface", -1) }
/Deleting volume: / { acted[id] = 1; add("volume", 1) }
/Cleanup failed: unable to delete volume: / { add("volume", -1) }
/Deleting security group: / { acted[id] = 1; add("security group", 1) }
/Cleanup failed: unable to delete security group: / { add("security group", -1) }
/Deleting key pair: / { acted[id] = 1; add("key pair", 1) }
/Cleanup failed: unable to delete key pair: / { add("key pair", -1) }
/Deleting orphaned snapshot: / { acted[id] = 1; add("snapshot", 1) }
/Cleanup failed: unable to delete orphaned snapshot: / { add("snapshot", -1) }

END {
	n = split("testinfra instance,Packer instance,network interface,volume,security group,key pair,snapshot", kinds, ",")
	line = region "\t" (failed + 0)
	for (i = 1; i <= n; i++) {
		c = count[kinds[i]] + 0
		line = line "\t" (c > 0 ? c : 0)
	}

	processed = ghosts = 0
	for (e in started) {
		processed++
		if (complete[e] && !acted[e] && !failed_id[e]) ghosts++
	}
	still = found > processed ? found - processed : 0
	print line "\t" ghosts "\t" still
}
' "$log"
