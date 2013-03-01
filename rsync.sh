#!/bin/ksh

#
# Author: Leland Sindt
#
# designed for OSX... but should be easily modified to work with most any *nix shell.
#
#

script=`basename $0`
copies=30
pad="00000000000000"

source="/Users/username/"
destination="/storage/data/Backups/username/Air/backups/"
dest_server="dest.server.com"
dest_user="username"

BSSID="0:00:00:00:00:00"

function getBSSID {
  /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep BSSID | awk -F " " {'print $2'}
}

if [[ "$(getBSSID)" != ${BSSID} ]]
then
  echo "Not associated with home network... quitting..."
  exit 0
else
  echo "Associated with home network."
fi

ping -t 1 ${dest_server} > /dev/null 2>&1
if [[ $? -eq 0 ]]
then
  echo "able to resolve and ping ${dest_server}"
else
  echo "unable to resolve and ping ${dest_server}"
  exit 0
fi

ssh ${dest_user}@${dest_server} "echo \"Hello World\"" > /dev/null 2>&1
if [[ $? -eq 0 ]]
then
  echo "able to ssh to ${dest_server}"
else
  echo "unable to ssh to ${dest_server}"
  exit 0
fi

ssh ${dest_user}@${dest_server} "ls ${destination}../ |grep $(date +%Y.%m.%d)" > /dev/null 2>&1
if [[ $? -eq 0 ]]
then
  echo "We already have a successful backup today. Quitting"
  exit 0
fi

function newestBackup  {
  latestFile=$(ssh ${dest_user}@${dest_server} "ls -d ${destination}backup* | tail -1")
  #echo $((10#$(echo "${latestFile}" | awk -F "." {'print $2'})*1))
  echo "${latestFile}" | awk -F "." {'print $2'}
}

function oldestBackup  {
  latestFile=$(ssh ${dest_user}@${dest_server} "ls -dr ${destination}backup* | tail -1")
  #echo $((10#$(echo "${latestFile}" | awk -F "." {'print $2'})*1))
  echo "${latestFile}" | awk -F "." {'print $2'}
}

function getbackupDateTime {
  ssh ${dest_user}@${dest_server} "[[ -e ${destination}backup.${1}/backupdatetime ]] && cat ${destination}backup.${1}/backupdatetime"
}

function createLock {
  #Create a Lock Directory
  mkdir /tmp/${script} > /dev/null 2>&1
  #Did the creation of the Lock fail?
  if [[ $? -eq  0 ]]
  then
    # No, continue normally
    echo "${script} starting"
    # store the curent pid in the lock dir
    echo $$ > /tmp/${script}/pid
  else
    #is the previous lock still valid? Is it still running?
    ps aux | grep -v grep |grep `cat /tmp/${script}/pid` |grep ${script}
    if [[ $? -eq 0 ]]
    then
      # Yes, exit.
      echo "${script} already running... "
      exit 0
    else
      # No, take the lock....
      echo "${script} appears to have failed last time..... taking over..."
      echo $$ > /tmp/${script}/pid
    fi
  fi
}

function removeLock {
  #remove the lock.
  rm -rf /tmp/${script}
}

createLock

#Did the previous backup complete?
ssh ${dest_user}@${dest_server} "ls ${destination}PreviousBackupSuccessful" > /dev/null 2>&1
if [[ $? -eq 0 ]]
then
  echo "Previous Backup Success"
  backup=$(oldestBackup)
  backupdatetime=$(getbackupDateTime ${backup})
  copycount=$(ssh ${dest_user}@${dest_server} "ls -d ${destination}backup* | wc -l ")
  if [[ ${copycount} -gt ${copies} ]] 
  then 
    echo "Delete Oldest"
    ssh ${dest_user}@${dest_server} "[[ -h ${destination}../${backupdatetime} ]] && rm ${destination}../${backupdatetime}; rm -rf ${destination}backup.${backup}"
  fi
  #clear previous backup success
  ssh ${dest_user}@${dest_server} "rm ${destination}PreviousBackupSuccessful"
else 
  echo "Previous Backup Fail -- Delete Newest Backup"
  backup=$(newestBackup)
  backupdatetime=$(getbackupDateTime ${backup})
  ssh ${dest_user}@${dest_server} "[[ -h ${destination}../${backupdatetime} ]] && rm ${destination}../${backupdatetime}; rm -rf ${destination}backup.${backup}"
fi

#There is a possible condition here where the previous unsuccessful packup is deleted, and the next backup is also unsucessful, but unable to create a backup.000# before the script fails. The following run will delete the newest backup again. This is a problem becuae the backup that was deleted was a success... nextbackup should be calculated as a part of the previous delete, and the directory should be created at time of delete.....  

backup=$(newestBackup)
nextbackup=$((10#${backup}*1+1))
nextbackup="$(echo ${pad} | cut -c 1-$((${#pad}-${#nextbackup})))${nextbackup}"

echo "Start rsync"
# run rsync... referencing the previous backup for hardlinks.
txtCommand="rsync -a -e ssh --delete --exclude .Trash --link-dest=../backup.${backup}  ${source} ${dest_user}@${dest_server}:${destination}backup.${nextbackup}/ > /dev/null 2>&1"
#txtCommand="rsync -av -e ssh --delete --exclude .Trash --link-dest=../backup.${backup}  ${source} ${dest_user}@${dest_server}:${destination}backup.${nextbackup}/ "
#echo ${txtCommand}
eval ${txtCommand}
rsyncreturn=$?
#rsyncreturn=0
echo "End rsync"

# Did rsync complete?
if [[ ${rsyncreturn} -eq 0 || ${rsyncreturn} -eq 24 ]]
then
  # Yes, note the backup time, and the Successful backup.
  ssh ${dest_user}@${dest_server} "echo `date +%Y.%m.%d_%H.%M.%S` > ${destination}backup.${nextbackup}/backupdatetime"
  backupdatetime=$(getbackupDateTime ${nextbackup})
  if [[ ! ${backupdatetime} == "" ]] 
  then
    ssh ${dest_user}@${dest_server} "[[ -h ${destination}../${backupdatetime} ]] && rm ${destination}../${backupdatetime}"
    ssh ${dest_user}@${dest_server} "[[ ! -h ${destination}../${backupdatetime} ]] && ln -s ${destination}backup.${nextbackup} ${destination}../${backupdatetime}" 
  fi

  ssh ${dest_user}@${dest_server} "echo ${rsyncreturn} > ${destination}PreviousBackupSuccessful"
  echo "Backup Success: ${rsyncreturn}"
else 
  # No, note it failed....
  echo "Backup Failed: ${rsyncreturn}"
  #exit ${rsyncreturn}
fi

removeLock

echo "done"
