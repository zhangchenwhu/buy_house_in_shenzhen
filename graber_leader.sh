#!/bin/bash

if (( $# != 4 )); then
exit 1
fi

PWD=$(cd "$(dirname "$0")";pwd)
pattern=$1
action=$2
followers=($3)
out=$4
echo $pattern
echo $action
echo ${followers[*]}
echo $out
declare -a outfd
declare -a infd
declare -a startPage
declare -a endPage
lock=3
fd=4

#function define
beforeExit() {
  closeAllOutPipe
  emptyAllSubOutFile
} 

closeAllOutPipe()
{
  for (( i = 0; i < ${#outfd[*]}; i++ )); do
    redir="${outfd[$i]}>&-"
    eval exec $redir 
  done
}

emptyAllSubOutFile()
{
  for (( i = 0; i < ${#followers[*]}; i++ )); do
    rm -f ${followers[$i]}.out
  done
}

#parse parameter
parameters=`./house_graber_split.sh "${followers[*]}"`
for ((i=0; i < ${#followers[*]}; i++ )); do
  line=$((i+1))
  startPage[$i]=`echo "$parameters" | sed -n "${line}p" | cut -d "\"" -f2 | cut -d " " -f2`
  endPage[$i]=`echo "$parameters" | sed -n "${line}p" | cut -d "\"" -f2 | cut -d " " -f3`
done

#set up connect and pipe
for (( i=0; i < ${#followers[*]}; i++ )); do
  msginFile=/tmp/`./uuid.sh`
  msgoutFile=/tmp/`./uuid.sh`
  mkfifo $msginFile
  mkfifo $msgoutFile

  {
    exec 3<$msgoutFile
    exec 4>$msginFile
    host=`echo ${followers[$i]} | cut -d ":" -f1`
    port=`echo ${followers[$i]} | cut -d ":" -f2`
    ncat $host $port <&3 >&4 2>/dev/null 
  } &

  redir="$fd>$msgoutFile"
  eval exec $redir 
  outfd[$i]=$fd
  ((fd++))
  redir="$fd<$msginFile"
  eval exec $redir 
  infd[$i]=$fd
  ((fd++))

  rm -f $msginFile $msgoutFile
done

#check array length
if (( !(${#followers[*]} == ${#infd[*]}  && ${#infd[*]} == ${#outfd[*]} && ${#outfd[*]} == ${#startPage[*]} &&  ${#startPage[*]} == ${#endPage[*]}) )); then
  echo "internal error!"
  beforeExit
  exit 1 
fi

#signal handle
trap "closeAllOutPipe; exit 0" TERM INT

#read from pipe loop 
declare -a isover
exec 3>"$PWD/writelock"
while ((1)); do
  shallStart=`date +%R | grep "$pattern"`
  if [ -z "$shallStart" ]; then
    sleep 600
    continue
  fi

  overCounter=0
  for (( i = 0; i < ${#infd[*]}; i++ )); do
    isover[$i]=0
  done
  emptyAllSubOutFile

  #start grab
  msg="`./send_ts.sh` start dispatch task..."
  echo "$msg"
  ./post_dingding_msg.sh "$msg" 
  for (( i=0; i < ${#followers[*]}; i++ )); do
    delay=`date +%s`
    delay=$(( delay % 10))
    sleep $delay
    echo `./send_ts.sh` ${followers[$i]} ${startPage[$i]} ${endPage[$i]}
    echo $action ${startPage[$i]} ${endPage[$i]} >& ${outfd[$i]}
  done

  while (( overCounter < ${#infd[*]} )); do
    for (( i = 0; i < ${#infd[*]}; i++ )); do
      if (( ${isover[$i]} == 1 )); then
        continue
      fi
      read -u ${infd[$i]} -t 180 
      if (( $? != 0 )); then
        ts=`./send_ts.sh`
        ./post_dingding_msg.sh "$ts graber leader read ${followers[$i]} time out, retry!"
        continue
      fi
      if [ "$REPLY" == "EOF" ]; then
        ((overCounter++))
        isover[$i]=1
      else
        echo "$REPLY" >> ${followers[i]}.out
      fi 
    done
  done

  flock $lock
  cat /dev/null > $out
  for (( i=0; i < ${#followers[*]}; i++ )); do
    cat ${followers[$i]}.out >> $out
  done
  flock -u $lock
  ts=`./send_ts.sh`
  ./post_dingding_msg.sh "$ts graber task success!"
  echo  "$ts graber task success!"
done