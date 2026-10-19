#!/usr/bin/env bash

set -euo pipefail

# Builds the Slack message payload (JSON on stdout) for the stale-resource cleanup workflow from the per-region lines written by ci/summarize-cleanup-log.sh
# When anything was cleaned or failed, the message has a Slack table block with one row per region and one column per resource type.
#
# Usage: build-slack-payload.sh [summary-file...]
# Environment:
#   RUN_URL (link to the run)
#   CLEANUP_RESULT (result of the cleanup job)
#   SLACK_CHANNEL (channel to post to)

: "${CLEANUP_RESULT:?CLEANUP_RESULT must be set}"
: "${RUN_URL:?RUN_URL must be set}"
: "${SLACK_CHANNEL:?SLACK_CHANNEL must be set}"

input=""
if (($# > 0)); then
	input=$(cat "$@")
fi

printf '%s\n' "$input" | jq -nR \
	--arg url "$RUN_URL" \
	--arg result "$CLEANUP_RESULT" \
	--arg channel "$SLACK_CHANNEL" '
def cell($t): {type: "raw_text", text: ($t | tostring)};
def na: .[1] == "n/a";
def total: if na then "n/a" else (.[2:9] | map(tonumber) | add) end;
def duration:
  if na or (.[11] // "n/a") == "n/a" then "n/a"
  else (.[11] | tonumber | floor) as $s
    | ($s / 3600 | floor) as $h
    | ($s % 3600 / 60 | floor) as $m
    | ($s % 60 | tostring | if length < 2 then "0" + . else . end) as $sec
    | if $h > 0 then "\($h)h \($m | tostring | if length < 2 then "0" + . else . end)m \($sec)s" else "\($m)m \($sec)s" end
  end;

# column headers, kept short so the table fits; the seven values after the region are the
# resource types in the order ci/summarize-cleanup-log.sh writes them
def headers: ["region", "testinfra", "Packer", "net ifs", "volumes", "sec groups", "key pairs", "snapshots", "TOTAL", "failed", "ghosts", "to clean", "duration"];
def region_row:
  [cell(.[0])]
  + (if na then [range(headers | length - 1) | cell("n/a")]
     else [.[2:9][] | cell(.)] + [cell(total), cell(.[1]), cell(.[9]), cell(.[10]), cell(duration)] end);

[inputs | select(length > 0) | split("\t")] | sort_by(.[0]) as $rows
| ($result != "success") as $jobfailed
| ($rows | any(.[]; na or ((.[1] | tonumber) > 0))) as $regionfailed
| ($rows | any(.[]; na or ((.[1] | tonumber) > 0) or (total | tonumber) > 0)) as $active
| (if $jobfailed or $regionfailed or ($rows | length) == 0 then ":red_circle:" else ":large_green_circle:" end) as $status
| (if ($rows | length) == 0 then
     [{type: "section", text: {type: "mrkdwn", text: "No cleanup summaries were produced"}}]
   elif ($active | not) then
     [{type: "section", text: {type: "mrkdwn", text: "Nothing to clean up"}}]
   else
     [{
       type: "table",
       column_settings: ([{align: "left"}] + (headers[1:] | map({align: "right"}))),
       rows: ([headers | map(cell(.))] + ($rows | map(region_row)))
     }]
   end) as $body
| {
    text: "Stale build resource cleanup",
    username: "postgres stale resources janitor",
    icon_emoji: ":supa-cat:",
    channel: $channel,
    blocks: (
      [{type: "section", text: {type: "mrkdwn", text: "\($status) *Stale build resource cleanup*"}}]
      + $body
      + [{type: "context", elements: [{type: "mrkdwn", text: ((if $jobfailed then "Cleanup job result: \($result) · " else "" end) + "<\($url)|View run>")}]}]
    )
  }
'
