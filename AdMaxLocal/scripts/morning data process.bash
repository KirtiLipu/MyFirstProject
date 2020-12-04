[TSAApp@aml12-core1 bidmgr]$ cat morning-data-process.sh
#!/bin/bash


test=0
do=""

while [ $# -gt 0 ]
do
    case "$1" in
        -t)               do="echo"; test=1;;
        --config-file)    shift;;
        --date)        shift; refdate=$1;;
        --discrepStartDate) shift; discrepStartDate=$1;;
        --discrepEndDate) shift; discrepEndDate=$1;;
    esac
    shift
done


DATEFMT="+%Y-%m-%d"
server_timezone=$TZ
reseller_timezone=$(/usr/local/tsa/bidmgr/get_reseller_timezone.sh)
if [ $reseller_timezone ]; then
    echo "reseller timezone = $reseller_timezone"
fi

if [ ! $refdate ]; then
    if [ $reseller_timezone ]; then
        refdate=`TZ="$reseller_timezone" date -d "1 day ago" $DATEFMT`
    else
        refdate=`date -d "1 day ago" $DATEFMT`
    fi
fi

if [ ! $discrepStartDate ]; then
    if [ $reseller_timezone ]; then
        discrepStartDate=`TZ="$reseller_timezone" date -d "10 days ago" $DATEFMT`
    else
        discrepStartDate=`date -d "10 days ago" $DATEFMT`
    fi
fi

if [ ! $discrepEndDate ]; then
    if [ $reseller_timezone ]; then
        discrepEndDate=`TZ="$reseller_timezone" date -d "2 days ago" $DATEFMT`
    else
        discrepEndDate=`date -d "2 days ago" $DATEFMT`
    fi
fi

#set timezone back to server timezone
TZ=$server_timezone

echo "refdate $refdate; discrepStartDate $discrepStartDate; discrepEndDate $discrepEndDate"

#
# Summarize Google Data
#
$do /usr/local/tsa/bidmgr/crontab-wrapper.sh --script sepull3.sh -d3 --date $refdate &


#
# Summarize Bing Data
#
$do /usr/local/tsa/bidmgr/crontab-wrapper.sh --script sepull147.sh -d3 --date $refdate &

#
# wait until summarization is finished
#
wait

#
# Run Warehouse Summarization
#
$do /usr/local/tsa/bidmgr/crontab-wrapper.sh --script whsumm.sh -d3 --date $refdate --lowgran


#
# Run SE Data Check Google
#
$do /usr/local/tsa/bidmgr/crontab-wrapper.sh --script sedatacheck-morning.sh -d3 --distribution 3

#
# Run SE Data Check Bing
#
$do /usr/local/tsa/bidmgr/crontab-wrapper.sh --script sedatacheck-morning-bing.sh -d3 --distribution 147



sedatacheck-morning:
---------------------

[TSAApp@aml12-core1 bidmgr]$ cat sedatacheck-morning.sh
#!/bin/sh

#
# Run the Search Engine Data Checker
#

refdate=""
sdebug=""
debug=""
params=""

while [ $# -gt 0 ]
do
    case "$1" in
        -d*)    sdebug="-d"; debug="$1";;
        --date) shift; refdate=$1;;
        -*)     params="$params $1 $2";;
    esac
    shift
done

DATEFMT="+%Y-%m-%d"

if [ $refdate ]; then
    enddate=`date -d "$refdate +1 day" $DATEFMT`
else
    #
    # default to day before yesterday (end date is exclusive)
    #
    #enddate=`date -d yesterday $DATEFMT`

    #
    # make that today
    #
    enddate=`date $DATEFMT`
fi

# go back 10 days
#
startdate=`date -d "$enddate -11 days" $DATEFMT`

DIR="/usr/local/tsa/bidmgr"


echo "================= Starting Search Engine Data Checker with [$debug --daily --date $startdate --end $enddate --force $params]"
$DIR/sedatacheck.sh $debug --date $startdate --end $enddate --force $params

admax-process:
------------- 
#!/bin/bash

STAGING_DATA_LOOP_TIME=10
PID_FILE_PREFIX=admax-process-
SCRIPT_DIR=/usr/local/tsa/bidmgr

# Distribution-specific arrays
DISTRIBUTION_NAME_ARRAY=(google bing yahoojapan)
DISTRIBUTION_ID_ARRAY=(3 147 178)
DISTRIBUTION_EARLIEST_START_TIME_ARRAY=(400 600 600)
DISTRIBUTION_RUN_ARRAY=(0 0 0)
DISTRIBUTION_START_TIME_ARRAY=(0 0 0)
DISTRIBUTION_PID_ARRAY=(0 0 0)
DISTRIBUTION_COMPLETE_ARRAY=(0 0 0)
DISTRIBUTION_EXIT_STATUS_ARRAY=(1 1 1)
DISTRIBUTION_TIMEOUT_ARRAY=(7200 7200 10800)

TIME_ZONE_PARAMS=""
TIME_ZONE_ARRAY=()

function getYesterday {
    local server_timezone=$TZ
    local yesterday=""

    for ((i=0; i<${#TIME_ZONE_ARRAY[*]}; i++));
    do
        local reseller_timezone=${TIME_ZONE_ARRAY[$i]}

        local reseller_yesterday=`TZ="$reseller_timezone" date --date=yesterday +%Y-%m-%d`

        if [ ! $yesterday ]
        then
            yesterday=$reseller_yesterday
        else
            if [ "$yesterday" != "$reseller_yesterday" ]
            then
                yesterday=""
                break
            fi
        fi
    done

    #set timezone back to server timezone
    TZ=$server_timezone

    echo "$yesterday"
}

function getEarliestCurrentTime {
    local server_timezone=$TZ
    local current_time=""

    for ((i=0; i<${#TIME_ZONE_ARRAY[*]}; i++));
    do
        local reseller_timezone=${TIME_ZONE_ARRAY[$i]}

        local reseller_time=`TZ="$reseller_timezone" date +%k%0M`

        reseller_time=${reseller_time//0}

        if [ ! $current_time ]
        then
            current_time=$reseller_time
        else
            if [[ $current_time -gt $reseller_time ]]
            then
                current_time=$reseller_time
            fi
        fi
    done

    #set timezone back to server timezone
    TZ=$server_timezone

    echo "$current_time"
}

function parseParams {
    local use_all_distributions=1

    while [ $# -gt 0 ]
    do
        case "$1" in
            -T|--date)          shift; refdate=$1;;
            -S|--distribution)  shift; parseDistributions $1; ret=$?; use_all_distributions=0; if [ $ret -eq 1 ]; then terminate; fi;;
            -z|--timezone)      shift; parseTimeZones $1;;
            -t)                 do="echo"; test=$1;;
            --force)            force="--force";;
            --help)             displayUsage; exit 0;;
            -*)                 params="$params $1";;
            *)
        esac
        shift
    done

    #Check that time zone(s) were specified
    if [ ${#TIME_ZONE_ARRAY[*]} -eq 0 ]; then
        terminate "Error: No time zones specified"
    fi

    #Set default date if none was specified
    if [ ! $refdate ]; then
        refdate=$(getYesterday)

        if [ ! $refdate ]
        then
            if [ ${#TIME_ZONE_ARRAY[*]} > 1 ]; then
                terminate "Error - Time zones' dates don't match"
            else
                terminate "Error - Could not retrieve processing date"
            fi
        fi
    fi

    if [ $use_all_distributions -eq 1 ]
    then
        for ((i=0; i<${#DISTRIBUTION_RUN_ARRAY[*]}; i++));
        do
            DISTRIBUTION_RUN_ARRAY[$i]=1
        done
    fi
}

function parseDistributions {
    local all_valid=1

    local invalid_distributions=""

    for distribution in `echo $1 | tr , " "`
    do
        local valid=0
        local index=0

        #Check if distribution is valid
        for valid_distribution in "${DISTRIBUTION_NAME_ARRAY[@]}"
        do
            if [ "$distribution" == "$valid_distribution" ]
            then
                let "valid|=1"
                DISTRIBUTION_RUN_ARRAY[$index]=1
            fi

            let "index++"
        done

        if [ $valid -eq 0 ]
        then
            invalid_distributions+="$distribution "
        fi

        let "all_valid&=valid"
    done

    #Display bad distribution list
    if [ $all_valid -eq 0 ]; then echo "Error - Invalid distributions: $invalid_distributions"; fi

    let "all_valid=1-$all_valid"

    return $all_valid
}

function parseTimeZones {
    TIME_ZONE_PARAMS=$1

    for timezone in `echo $1 | tr , " "`
    do
        TIME_ZONE_ARRAY+=($timezone)
    done

    return ${#TIME_ZONE_ARRAY[*]}
}

function displayUsage {
    echo "To run script to process yesterday's data for all distributions:"
    echo " $(basename $BASH_SOURCE) -z <time zones to process>"
    echo "To run script to process a specific date:"
    echo " $(basename $BASH_SOURCE) --date <date to process> -z <time zones to process>"
    echo "To run script to process a specific distribution:"
    echo " $(basename $BASH_SOURCE) -S <distribution name> -z <time zones to process>"
    echo "To run script with a specified debug level:"
    echo " $(basename $BASH_SOURCE) -d3 -z <time zones to process>"
}

function terminate {
    if [ $# -gt 0 ]
    then
        echo $@
    fi

    exit 1
}

function getRunCount {
    local count=0

    for run in "${DISTRIBUTION_RUN_ARRAY[@]}"
    do
        if [ $run -eq 1 ]
        then
            let "count++"
        fi
    done

    return $count
}

function getPIDCount {
    local count=0

    for pid in "${DISTRIBUTION_PID_ARRAY[@]}"
    do
        if [ $pid -ne 0 ]
        then
            let "count++"
        fi
    done

    return $count
}

function getCompleteCount {
    local count=0

    for complete in "${DISTRIBUTION_COMPLETE_ARRAY[@]}"
    do
        if [ $complete -eq 1 ]
        then
            let "count++"
        fi
    done

    return $count
}

function cleanup_staging_tmp_files {
    #Remove any remaining staging temp files
    rm -f /tmp/$PID_FILE_PREFIX*
}

function startStagingData {
    trap "cleanup_staging_tmp_files; exit 1" SIGHUP SIGINT SIGTERM

    local old_pid_count=0

    getRunCount
    local run_count=$?

    while :
    do
        local index=0

        for run in "${DISTRIBUTION_RUN_ARRAY[@]}"
        do
            #Check if this distribution should be run
            if [ $run -eq 1 ]
            then
                #Check if distribution is already running
                if [ ${DISTRIBUTION_PID_ARRAY[$index]} -eq 0 ]
                then
                    local yesterday=$(getYesterday)
                    local now=$(getEarliestCurrentTime)

                    #Check if refdate is yesterday and earliest start time is past
                    if [[ $yesterday != $refdate ]] || [[ $now -ge ${DISTRIBUTION_EARLIEST_START_TIME_ARRAY[$index]} ]]
                    then
                        $SCRIPT_DIR/admax-staging-process.sh $PID_FILE_PREFIX ${DISTRIBUTION_NAME_ARRAY[$index]} --date $refdate $test $force $params -z ${TIME_ZONE_PARAMS} &
                        DISTRIBUTION_PID_ARRAY[$index]=$!
                        DISTRIBUTION_START_TIME_ARRAY[$index]=`date +%s`
                    fi
                fi
            fi

            let "index++"
        done

        getPIDCount
        local pid_count=$?

        #Check if all the desired processes have been started
        if [ $pid_count -lt $run_count ]
        then
            if [ $old_pid_count -ne $pid_count ]
            then
                old_pid_count=$pid_count

                echo "$pid_count out of $run_count processes run ..."
            fi

            sleep $STAGING_DATA_LOOP_TIME
        else
            echo "All staging data processes ($run_count) started"
            break
        fi
    done
}

function waitForStagingDataCompletion {
    local old_complete_count=0

    getPIDCount
    local pid_count=$?

    while :
    do
        local index=0

        for pid in "${DISTRIBUTION_PID_ARRAY[@]}"
        do
            #Check if this distribution was run
            if [ $pid -ne 0 ]
            then
                #Check if not already finished
                if [ ${DISTRIBUTION_COMPLETE_ARRAY[$index]} -eq 0 ]
                then
                    #Check if still running
                    if [ ! -d /proc/$pid ]
                    then
                        DISTRIBUTION_COMPLETE_ARRAY[$index]=1
                        if [ -f /tmp/$PID_FILE_PREFIX$pid ]
                        then
                            DISTRIBUTION_EXIT_STATUS_ARRAY[$index]=`cat /tmp/$PID_FILE_PREFIX$pid`
                        else
                            DISTRIBUTION_EXIT_STATUS_ARRAY[$index]=-1
                        fi
                    else
                        local duration=0
                        local now=`date +%s`

                        let duration=$now-${DISTRIBUTION_START_TIME_ARRAY[$index]}

                        echo "Checking timeout for ${DISTRIBUTION_PID_ARRAY[$index]} ... duration is $duration"

                        #Check timeout
                        if [ $duration -gt ${DISTRIBUTION_TIMEOUT_ARRAY[$index]} ]
                        then
                            DISTRIBUTION_COMPLETE_ARRAY[$index]=1
                            DISTRIBUTION_EXIT_STATUS_ARRAY[$index]=1
                        fi
                    fi
                fi
            fi

            let "index++"
        done

        getCompleteCount
        local complete_count=$?

        #Check if all the desired processes have completed
        if [ $complete_count -lt $pid_count ]
        then
            if [ $old_complete_count -ne $complete_count ]
            then
                old_complete_count=$complete_count

                echo "$complete_count out of $pid_count processes complete ..."
            fi

            sleep $STAGING_DATA_LOOP_TIME
        else
            echo "All staging data processes ($pid_count) complete"
            break
        fi
    done

    echo ${DISTRIBUTION_EXIT_STATUS_ARRAY[*]}

    cleanup_staging_tmp_files
}

function runABU {
    local index=0

    for exit_status in "${DISTRIBUTION_EXIT_STATUS_ARRAY[@]}"
    do
        #Check if staging process succeeded
        if [ $exit_status -eq 0 ]
        then
            local distribution_id=${DISTRIBUTION_ID_ARRAY[$index]}

            echo "=================== Starting ABU with [--date $refdate -d3 --distribution $distribution_id -z ${TIME_ZONE_PARAMS}]"

            $do $SCRIPT_DIR/admax.sh --date $refdate -d3 --distribution $distribution_id -z ${TIME_ZONE_PARAMS}
        else
            echo "Not running ABU for ${DISTRIBUTION_NAME_ARRAY[$index]}"
        fi

        let "index++"
    done
}

function runBidUpdater {
    local index=0

    for exit_status in "${DISTRIBUTION_EXIT_STATUS_ARRAY[@]}"
    do
        #Check if staging process succeeded
        if [ $exit_status -eq 0 ]
        then
            local distribution_id=${DISTRIBUTION_ID_ARRAY[$index]}

            echo "=================== Starting AdMax Bid Updater with [-d3 --distribution $distribution_id]"

            $do $SCRIPT_DIR/sebidupdater.sh -d3 --distribution $distribution_id
        else
            echo "Not running BidUpdater for ${DISTRIBUTION_NAME_ARRAY[$index]}"
        fi

        let "index++"
    done
}

function runBidIssueNotification {
    echo "=================== Checking for AdMax Bid Updater Issues"

    $do $SCRIPT_DIR/bidIssueNotification.sh
}

function process {
    parseParams $*

    startStagingData

    waitForStagingDataCompletion

    runABU

    runBidUpdater

    runBidIssueNotification
}

process $*




[TSAApp@aml27-core1 bidmgr]$ cat crontab-wrapper.sh
#!/bin/bash

###########################################################
# Script to wrap cronjobs in. Used so we can see the output
# as the process is running. Creates a directory and uses
# tee to write output to a log file.
#
# Log file stored in $logdirs/YYYY-MM-DD/$script_HH.log
# If a log file exists it will be appended to.
###########################################################

params=""
test=0
do=""
script=""
DIR="/usr/local/tsa/bidmgr"

logdirdate=`date +%Y-%m-%d`
hour=`date +%H`

logdirs="/var/local/tsa/log /var/log /tmp"

while [ $# -gt 0 ]
do
    case "$1" in
        --date)          params="$params $1"; logdirdate=`date -d "$2 +1 day" +%Y-%m-%d`;;
        --script)        shift; script=$1;;
        -t)              do="echo"; test=1;;
        -*|*)            params="$params $1";;
    esac
    shift
done

logfile="${script}_${hour}.log"
logfile=`basename $logfile`

err=0;

if [ ! "$script" ]; then
    echo "No script specified, exiting";
    exit 1;
fi

if [ ! -e "$DIR/$script" ]; then
    echo "$DIR/$script does not exist, exiting";
    exit 1;
fi

# Determine a writeable log dir in order of preference
# (taken from dbreplicator-tsacommon.sh)
for logdir in $logdirs
do
    if [ -w $logdir ] ; then
        logdir=${logdir}/$logdirdate

        if [ ! -e $logdir ]; then
            mkdir $logdir
            chmod g+w $logdir
            chgrp tsaapp $logdir
        fi

        log="$logdir/$logfile"

#        if [ -e $log ]; then
#            ts=`date +%H%M%S`
#            echo "Moving previously existing log file to $log.$ts"
#            mv $log $log.$ts
#        fi

        echo "Logging to $log"
        break
    fi
done

if [ $test -eq 1 ]; then
    echo "Warning: Testing mode enabled for crontab-wrapper.sh"
fi



echo "Executing $script $params"
$do $DIR/$script $params &> $log || err=1


[TSAApp@aml27-core1 bidmgr]$ cat morning-data-process-yj.sh
#!/bin/bash


test=0
do=""

while [ $# -gt 0 ]
do
    case "$1" in
        -t)               do="echo"; test=1;;
        -c|--config-file) config="$1 $2"; shift;;
        --date)        shift; refdate=$1;;
        --discrepStartDate) shift; discrepStartDate=$1;;
        --discrepEndDate) shift; discrepEndDate=$1;;
    esac
    shift
done


DATEFMT="+%Y-%m-%d"
server_timezone=$TZ
reseller_timezone=$(/usr/local/tsa/bidmgr/get_reseller_timezone.sh)
if [ $reseller_timezone ]; then
    echo "reseller timezone = $reseller_timezone"
fi

if [ ! $refdate ]; then
    if [ $reseller_timezone ]; then
        refdate=`TZ="$reseller_timezone" date -d "1 day ago" $DATEFMT`
    else
        refdate=`date -d "1 day ago" $DATEFMT`
    fi
fi

if [ ! $discrepStartDate ]; then
    if [ $reseller_timezone ]; then
        discrepStartDate=`TZ="$reseller_timezone" date -d "10 days ago" $DATEFMT`
    else
        discrepStartDate=`date -d "10 days ago" $DATEFMT`
    fi
fi

if [ ! $discrepEndDate ]; then
    if [ $reseller_timezone ]; then
        discrepEndDate=`TZ="$reseller_timezone" date -d "2 days ago" $DATEFMT`
    else
        discrepEndDate=`date -d "2 days ago" $DATEFMT`
    fi
fi

#set timezone back to server timezone
TZ=$server_timezone

echo "refdate $refdate; discrepStartDate $discrepStartDate; discrepEndDate $discrepEndDate"

#
# Summarize YJ Data
#
$do /usr/local/tsa/bidmgr/crontab-wrapper.sh --script sepull-yj.sh -d3 --date $refdate --force $config


#
# Run SE Data Check
#
$do /usr/local/tsa/bidmgr/crontab-wrapper.sh --script sedatacheck-morning.sh -d3 --distribution 178

#
# Run Warehouse Summarization
#
$do /usr/local/tsa/bidmgr/crontab-wrapper.sh --script whsumm.sh -d3 --date $refdate --lowgran





