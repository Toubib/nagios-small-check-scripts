#!/bin/bash
# parse a statpack to generate a csv file
#
# https://github.com/Toubib/small-scripts

# CONTEXT INFOS
echo -n "Instance"
echo -n "; Host"

# DATE
echo -n "; Begin Snap"
echo -n "; End Snap"

# CONFIG
echo -n "; Buffer Cache"
echo -n "; Shared Pool"
echo -n "; Process"
echo -n "; Cursors"

# Load Profile

echo -n "; Load Profile: DB time(s) /s"
echo -n "; Load Profile: DB CPU(s) /s"
echo -n "; Load Profile: Redo size /s"
echo -n "; Load Profile: Logical reads /s"
echo -n "; Load Profile: Physical reads /s"
echo -n "; Load Profile: Physical writes /s"

# STATS
echo -n "; IO Stat by Function - summary: Direct Reads (M)"
echo -n "; IO Stat by Function - summary: Read Vol/sec (M)"
echo -n "; IO Stat by Function - summary: Direct Writes (M)"
echo -n "; IO Stat by Function - summary: Write Vol/sec (M)"


echo

#### GREP

function grep_str_field()
{
	STR=$1
	FIELD=$2
	$GREP "$STR" $FILE|head -n1|awk -v F=$FIELD '{printf ";" $F}'|sed -e 's/G/000M/' -e 's/M//' -e 's/,//g'  -e 's/\./,/g'
}

function grep_str_field_after_ref()
{
	REF_STR=$1
	STR=$2
	FIELD=$3
	$GREP -A15 "$REF_STR" $FILE |grep "$STR"|awk -v F=$FIELD '{printf ";" $F}' |sed -e 's/G/000M/' -e 's/M//' -e 's/,//g'  -e 's/\./,/g'
}

for FILE in $@
do

	case ${FILE##*.} in
		xz)
		GREP=xzgrep
		;;
		gz)
		GREP=zgrep
		;;
		*)
		GREP=grep
		;;
	esac
	
	# CONTEXT INFOS
	$GREP -A2  "^Database.*DB Id.*Instance" $FILE|tail -n1|awk '{printf $2}'
	$GREP -A3 "^Host" $FILE|tail -n1|awk '{printf ";" $1}'
	
	# DATE
	$GREP -A3 "Begin Snap:" $FILE|head -n1|awk '{printf ";" $4 " " $5}'
	$GREP -A3 "End Snap:" $FILE|head -n1|awk '{printf ";" $4 " " $5}'
	
	# CONFIG
	grep_str_field "Buffer Cache:" 3
	#$GREP -A3 "Buffer Cache:" $FILE|head -n1|awk '{printf ";" $3}'|sed -e 's/G/000/' -e 's/M//'
	$GREP -A3 "Shared Pool:" $FILE|head -n1|awk '{printf ";" $3}'|sed -e 's/G/000/' -e 's/M//'
	$GREP -A20 "Process Memory Summary Stats" $FILE|grep "^B ---"|awk '{printf ";" $NF}'
	$GREP "^opened cursors current" $FILE|awk '{printf ";" $NF}'
	
	# Load Profile
	#$GREP "DB time(s):" $FILE|head -n1|awk '{printf ";" $3}'
	grep_str_field "DB time(s):" 3
	grep_str_field "DB CPU(s):" 3
	grep_str_field "Redo size:" 3
	grep_str_field "Logical reads:" 3
	grep_str_field "Physical reads:" 3
	grep_str_field "Physical writes:" 3
	
	# STATS
	grep_str_field_after_ref "IO Stat by Function - summary" "Direct Reads" 3
	grep_str_field_after_ref "IO Stat by Function - summary" "Direct Reads" 5
	grep_str_field_after_ref "IO Stat by Function - summary" "Direct Writes" 6
	grep_str_field_after_ref "IO Stat by Function - summary" "Direct Writes" 8
	
	echo

done
