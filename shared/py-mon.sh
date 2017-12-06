#!/bin/bash

### CRONTAB:
###
### SHELL=/bin/bash
### * * * * * /mnt/py-mon-shared/py-mon.sh &>> /tmp/py-mon.log
###

PORT=8001
CHECK=$(netstat -an|grep $PORT|grep -i listen)
RUNFILE='/mnt/py-mon-shared/webserver.sh'
RUNLOG='/tmp/webserver.log'

if [ -z "$CHECK" ]; then
    echo 'run'
    nohup $RUNFILE &>> $RUNLOG &
else
    echo 'skip'
fi
