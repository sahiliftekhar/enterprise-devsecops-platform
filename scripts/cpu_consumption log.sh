#!/bin/bash
LOGFILE=/var/log/cpu_monitor.log
echo "=== $(date) ===" >> $LOGFILE
ps aux --sort=-%cpu | awk 'NR<=6{print $1,$2,$3,$11}' >> $LOGFILE
