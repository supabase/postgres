#!/bin/bash

: "${LOG_LEVEL:=info}"

echo "Starting salt-minion with log level $LOG_LEVEL"
/usr/bin/salt-minion --log-level="$LOG_LEVEL"
