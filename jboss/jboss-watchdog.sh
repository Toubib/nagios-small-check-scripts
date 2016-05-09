#!/bin/bash


INSTANCE=$1;shift
TEST=0
VERBOSE=0

while getopts "vta:" opt; do
  case $opt in
    v)
      VERBOSE=1
      ;;
    t)
      TEST=test
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      ;;
  esac
done

MAILTO=xxx
JBOSS_PATH=xxx
LOG_PATH=/xxx/logs/jboss-watchdog/$(date +%Y-%m)/$(date +%d)
LOG_FILE=$LOG_PATH/${INSTANCE}.log
WORK_PATH=/usr/local/var/jboss-watchdog
LAST_PATH=$WORK_PATH/last

CURTIME=$(date +%s)

INSTANCE_IS_RUNNING=0
FREEZE_TIMER=300 #seconds
SYSLOAD_MAX=32
AJP_THREAD_MAX_DEFAULT=180
DO_JSTACK=0
JBOSS_LOGFILE_MAX_SIZE=256000000 #256Mo

#process management
PID_FILE=/tmp/check-$INSTANCE.pid;CURRENTPID=$$
if [ -f $PID_FILE ];then
  OLDPID=`cat $PID_FILE`;SEARCHPID="x`ps -p $OLDPID -o pid h`"
  if [ "$SEARCHPID" != "x" ];then echo "Already launched (pid $OLDPID), exit"; exit 1;fi
fi
echo $CURRENTPID > $PID_FILE

function trace_echo()
{
	echo "[$(date +'%F %T')] $@"
	echo "[$(date +'%F %T')] $@" >> $LOG_FILE
}

function die()
{
	trace_echo "DIE $@"
	exit
}

function check_var_def()
{
    for i in $@
    do
        test -n "${!i}" || die "var [$i] is undef"
    done
}

function show_help()
{
	echo "help:"
	echo "$0 instance_name"
	exit
}

function send_event()
{
	ACTION=$1
	MESSAGE="$2"
	
	trace_echo "$MESSAGE"

	echo "$(date)" | mailx -s "[$HOSTNAME] jboss-watchdog - $ACTION $INSTANCE: $MESSAGE" $MAILTO
}

function jboss_action()
{
	ACTION=$1
	MESSAGE="$2"

	send_event $ACTION "$MESSAGE"
	trace_echo "=> /etc/init.d/jboss.$INSTANCE $ACTION"

	echo $ACTION > $LAST_PATH/${INSTANCE}.action

	if [ $DO_JSTACK -eq 1 ];then
		trace_echo "jstack $JBOSS_PID"
		/etc/init.d/jboss.$INSTANCE jstack
	fi

	if [ "$TEST" = "test" ];then
		echo "<TEST MODE> /etc/init.d/jboss.$INSTANCE $ACTION"
	else
		/etc/init.d/jboss.$INSTANCE $ACTION RPA $MESSAGE
	fi

	rm -f $PID_FILE
	exit
}

#Check if an action has be done recently and abort
function check_action_file_delay()
{
    ACTION_FILE_TIME=$(stat -c '%Y' $LAST_PATH/${INSTANCE}.action)
    ACTION_FILE_ELAPSED_TIME=$(( $CURTIME - $ACTION_FILE_TIME ))

    if [ $ACTION_FILE_ELAPSED_TIME -lt $FREEZE_TIMER ];then
        die "Last action delay = ${ACTION_FILE_ELAPSED_TIME}s (<${FREEZE_TIMER}s)"
    fi
}

set_is_jboss_running()
{
	JBOSS_PID=$(<$JBOSS_PATH/$INSTANCE/pid)
	
	#Test if the jboss instance is running
	ps $JBOSS_PID| grep -- "-c ${INSTANCE}$" | grep -v grep | grep -q $INSTANCE && INSTANCE_IS_RUNNING=1

	if [ $INSTANCE_IS_RUNNING -eq 1 ];then echo " - jboss is running"
	else echo " - jboss is not running" ; fi
}

function check_process_age()
{
	PROCESS_DATE=$(date -d "$(ps h -p $JBOSS_PID -o lstart=)" +%s)
	PROCESS_AGE=$(( $CURTIME - $PROCESS_DATE ))

    if [ $PROCESS_AGE -lt $FREEZE_TIMER ];then
		die "Process_age = ${PROCESS_AGE}s (<${FREEZE_TIMER}s)"
    fi
}

test_segfault()
{
	LAST_HS_FILE=$(ls -t $JBOSS_PATH/$INSTANCE/log/|grep "hs_err_pid[0-9]*.log"|head -n1)

	if [ -z "$LAST_HS_FILE" ] || [ ! -f $JBOSS_PATH/$INSTANCE/log/$LAST_HS_FILE ]
	then
		echo " - test segfault OK"
		return 1
	fi

	#grep "#.*pid=" $LAST_HS_FILE|tail -n1|sed -e 's/.*pid=//' -e 's/,.*//'
	HS_FILE_PID=$(echo $LAST_HS_FILE|sed -e 's/hs_err_pid//' -e 's/\.log//')

	if [ $JBOSS_PID -eq $HS_FILE_PID ]
	then
		echo " - test segfault ERROR [$LAST_HS_FILE]"
		return 0
	else
		echo " - test segfault OK"
		return 1
	fi
}

check_ajp()
{
	AJP_THREAD_COUNT=$(snmpget -v1 -Oqv -c xxx -t10 -r3 localhost:$JBOSS_SNMP_PORT .1.2.3.4.1.20)
	AJP_THREAD_COUNT_RET=$? 

	echo " - AJP_THREAD_COUNT: $AJP_THREAD_COUNT/$AJP_THREAD_MAX ($AJP_THREAD_COUNT_RET)"

	if [ $AJP_THREAD_COUNT_RET -gt 0 ]; then
		jboss_action restart "snmp failed with code $AJP_THREAD_COUNT_RET"
	fi

	if [ $AJP_THREAD_COUNT -gt $AJP_THREAD_MAX ]; then
		jboss_action restart "AJP threads $AJP_THREAD_COUNT > $AJP_THREAD_MAX"
	fi
}

check_cat_ds()
{
	CAT_DS_FREE=$(snmpget -v1 -Oqv -c xxx -t10 -r3 localhost:$JBOSS_SNMP_PORT .1.2.3.4.1.11)
	CAT_DS_FREE_RET=$?

	echo " - CAT_DS_FREE: $CAT_DS_FREE ($CAT_DS_FREE_RET)"

	if [ $CAT_DS_FREE_RET -gt 0 ]; then
		jboss_action restart "snmp failed with code $CAT_DS_FREE_RET"
	fi

	if [ $CAT_DS_FREE -eq 0 ]; then
		jboss_action restart "CAT_DS_FREE = 0"
	fi
}

check_datasource()
{
	DS_NAME=$1 #CAT/BOOK

	case $DS_NAME in
		CAT)
			SNMP_ID=.1.2.3.4.1.11
			;;
		FARE)
			SNMP_ID=.1.2.3.4.1.14
			;;
		BOOK)
			SNMP_ID=.1.2.3.4.1.17
			;;
		*)
			echo " - check_datasource [$DS_NAME] not found !"
			return
			;;
	esac

	DS_FREE=$(snmpget -v1 -Oqv -c xxx -t10 -r3 localhost:$JBOSS_SNMP_PORT $SNMP_ID)
	DS_FREE_RET=$?

	echo " - ${DS_NAME}_DS_FREE: $DS_FREE ($DS_FREE_RET)"

	if [ $DS_FREE_RET -gt 0 ]; then
		jboss_action restart "snmp failed with code $DS_FREE_RET"
	fi

	if [ $DS_FREE -eq 0 ]; then
		jboss_action restart "${DS_NAME}_DS_FREE = 0"
	fi
}

check_log_file_size()
{
	local LOG_FILE_SIZE=$(stat -c '%s' $JBOSS_PATH/$INSTANCE/log/server.log)

	echo " - LOG_FILE_SIZE: $(( $LOG_FILE_SIZE/1000/1000 ))/$(( $JBOSS_LOGFILE_MAX_SIZE/1000/1000 )) Mo"

	if [ $LOG_FILE_SIZE -gt $JBOSS_LOGFILE_MAX_SIZE ]; then
		jboss_action restart "server.log is $(( $LOG_FILE_SIZE/1000/1000 ))Mo, > $(( $JBOSS_LOGFILE_MAX_SIZE/1000/1000 ))Mo"
	fi
}

function grep_logs_oom()
{
	local RETCODE=1
	local RETDATA=$(grep -B1 -m1 "utOfMemory" $JBOSS_PATH/$INSTANCE/log/server.log)

	echo -n " - grep utOfMemory: "

	if [ -n "$RETDATA" ];then
			echo "found"
			RETCODE=0

	else
		echo "not found"
	fi

	return $RETCODE
}

function grep_logs_custom()
{
 	LOG2CATCH=$1
	LOGMAXCOUNT=$2
	LOGCOUNT=$(grep -c -m${LOGMAXCOUNT} "$LOG2CATCH" $JBOSS_PATH/$INSTANCE/log/server.log)

	echo -n " - grep $LOG2CATCH : "
        if [ $LOGCOUNT -ge $LOGMAXCOUNT ];then
                echo "found at least $LOGCOUNT time(s)"
		RETCODE=0
        else
                echo "not found"
		RETCODE=1
        fi

        return $RETCODE

}
function get_jboss_mem_info()
{
	grep -e "^JAVA_OPTS" $JBOSS_PATH/$INSTANCE/conf/JAVA_OPTS.sh|sed -e 's/.*Xmx//' -e 's/ .*//'
}

function check_server_load()
{
	SYSLOAD=$(awk 'BEGIN { printf ("%.0f", '$(uptime |sed -e "s/.*: //" -e "s/,.*//")' ) }')

	if [ $SYSLOAD -gt $SYSLOAD_MAX ];then
		die "system load error [$SYSLOAD > $SYSLOAD_MAX]"
	fi
}

if [ -z "$INSTANCE" ] || [ ! -d $JBOSS_PATH/$INSTANCE ]; then
	show_help
fi

test -d $LOG_PATH  || mkdir -p $LOG_PATH

test -f $JBOSS_PATH/$INSTANCE/conf/ts-config.sh || die "file [$INSTANCE/conf/ts-config.sh] not found"
test -f $JBOSS_PATH/$INSTANCE/log/server.log || die "file [$INSTANCE/log/server.log] not found"
test -f $JBOSS_PATH/$INSTANCE/pid || die "file [$JBOSS_PATH/$INSTANCE/pid] not found"
test -f /etc/init.d/jboss.$INSTANCE || die "file [/etc/init.d/jboss.$INSTANCE] not found"

test -d $WORK_PATH || mkdir -p $WORK_PATH
test -d $LAST_PATH || mkdir -p $LAST_PATH

if [ "$TEST" = "test" ];then
	echo "Test mode, no real actions."
fi

check_server_load

#Check wait time
test -f $LAST_PATH/${INSTANCE}.action && check_action_file_delay

#set vars
source $JBOSS_PATH/$INSTANCE/conf/ts-config.sh && check_var_def JBOSS_SNMP_PORT
test -z "$AJP_THREAD_MAX" && AJP_THREAD_MAX=$AJP_THREAD_MAX_DEFAULT
test "$SKIP_JBOSS_WATCHDOG" = "true" && die "skip enabled"

set_is_jboss_running

check_process_age

# TESTS BEGIN HERE

#Jboss is not running but should since we have a pid file.
if [ $INSTANCE_IS_RUNNING -eq 0 ]; then
	test_segfault && jboss_action restart "JVM segfault"

	# Should not happen !!
	die "$INSTANCE[$JBOSS_PID] not launched"
fi

check_log_file_size

# TEST OOM
grep_logs_oom && jboss_action restart "OOM found [$(get_jboss_mem_info)]"

# TEST LOG CUSTOM
grep_logs_custom "javax.naming.NameAlreadyBoundException; remaining name" 1 && jboss_action restart "Log: $log found"
grep_logs_custom "EJB3 is not registered" 2 && jboss_action restart "Log: $log found"

check_ajp

#CHECK_CAT_DS=0
test -n "$CHECK_CAT_DS" && check_datasource CAT
test -n "$CHECK_BOOK_DS" && check_datasource BOOK

trace_echo OK

rm -f $PID_FILE
