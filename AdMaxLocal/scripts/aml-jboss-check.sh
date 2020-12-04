#!/bin/bash
COUNT=1
JBOSS_COUNT=`ps -ef | grep jboss | wc -l`
STARTED=`egrep "Started in"  /home/TSAApp/apps/jboss-5.1.0.GA/tsa_messaging_node_server.log |wc -l`

if [ $JBOSS_COUNT -le $COUNT ]; then
        /bin/sh /home/TSAApp/apps/jboss-5.1.0.GA/start_tsa_messaging_node_server.sh
sleep 60

while [ "$STARTED" -eq "$COUNT" ]
        do
                /bin/sh /etc/init.d/tsa-admax-jmslistener.sh restart
                exit;
        done
fi