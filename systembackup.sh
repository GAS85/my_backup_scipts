#!/bin/bash

# By Georgiy Sitnikov.
#
# Will do system backup and upload encrypted to mega - NEEDS megatools
#
# AS-IS without any warranty

nonce=$(md5sum <<< $(ip route get 8.8.8.8 | awk '{print $NF; exit}')$(hostname) | cut -c1-5 )

# Please do not use root folder
WORKINGDIR=/home/backup

# Other settings
logfile=/var/log/backup_$nonce.log
SavePasswordLocal=true

#Folders to be excluded from backup
excludeFromBackup="--exclude=$WORKINGDIR\
 --exclude=/proc\
 --exclude=/tmp\
 --exclude=/mnt\
 --exclude=/dev\
 --exclude=/sys\
 --exclude=/run\
 --exclude=/media\
 --exclude=/var/log\
 --exclude=/var/cache/apt/archives\
 --exclude=/usr/src/linux-headers*\
 --exclude=/home/*/.gvfs\
 --exclude=/home/*/.cache\
 --exclude=/home/*/.local/share/Trash"

. /etc/systembackup.conf

LOCKFILE=/tmp/sysbackup_$nonce
EMAILFILE=/tmp/sysbackup_$nonce.mail
extension=.tar.gpg
BACKUPNAME=backup-$(date +"%Y-%m-%d")_$nonce$extension

if [ -f "$LOCKFILE" ]; then
	# Remove lock file if script fails last time and did not run longer than 35 days due to lock file.
	find "$LOCKFILE" -mtime +35 -type f -delete
	echo "$(date) - WARNING - Another instance blocked backup process."
	exit 1
fi

if [ ! -f "/etc/systembackup.conf" ]; then
	echo "$(date) - ERROR - Config file was not found under /etc/systembackup.conf. Will continuer with default settings."
else
	if [ ! -r "/etc/systembackup.conf" ]; then
		echo "$(date) - ERROR - Config file could not be read."
		exit 1
	fi
fi

# Put output to Logfile and Errors to Lockfile as per https://stackoverflow.com/questions/18460186/writing-outputs-to-log-file-and-console
exec 3>&1 1>>${logfile} 2>>${LOCKFILE}

#Check if Backup file name already taken
if [ -f "$BACKUPNAME" ]; then
        # Added time to Backup name
	echo "$(date) - WARNING - Backup file $BACKUPNAME exist, will take another name to create backup." | tee /dev/fd/3
	BACKUPNAME=backup-$(date +"%Y-%m-%d_%T")_$nonce$extension
fi

#Check if Working dir exist
if [ ! -d "$WORKINGDIR" ]; then
	echo "$(date) - Directory $WORKINGDIR does not exist" | tee /dev/fd/3
	exit 1
fi

touch $LOCKFILE
touch $EMAILFILE

start=`date +%s`

echo "$(date) - INFO - The backup process ($BACKUPNAME) has being started."

# Random password generator. 48 is a password lenght 
pass="$(gpg --armor --gen-random 1 48)"

cd $WORKINGDIR

# Do System backup
tar -cvp $excludeFromBackup --one-file-system / | gpg --passphrase "$pass" --symmetric --no-tty -o $BACKUPNAME

# Calculating SHA256 of backup file
sha=$(sha256sum $BACKUPNAME | awk '{printf "%s",$1}' | tr 'a-z' 'A-Z')

# Opt: save password locally if Email fails, or you do not want to send it.
if [ "$SavePasswordLocal" == true ]; then
	echo "$(date) - The backup ($BACKUPNAME) was created with password: $pass - SHA256 of backup file: $sha." >> $WORKINGDIR/passes.txt
fi
middle=`date +%s`

#Upload backup to Mega
upload_command="megaput -u $megalogin -p $megapass --no-progress --path /Root/Backup $BACKUPNAME"

NEXT_WAIT_TIME=10
until $upload_command || [ $NEXT_WAIT_TIME -eq 4 ]; do
   sleep $(( NEXT_WAIT_TIME++ ))
   echo "$(date) - ERROR - Mega Upload was failed, will retry after 10 seconds ($BACKUPNAME)."
done

#delete local old backups
# +45 is older than 45 days - basically any other backup.
#find "$ToFind" -mtime +45 -exec rm {} \; 2>>$LOCKFILE
find backup*gpg -mtime +45 -exec rm {} \;

end=`date +%s`

#put collected data into logfile
[ -s $LOCKFILE ] && cat $LOCKFILE >> $logfile

#Email Header
echo 'To: '$recipients'
FROM: '$from'
Subject: '$subject'
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="-q1w2e3r4t5"

---q1w2e3r4t5
Content-Type: text/html
Content-Disposition: inline

The backup was created with password: '"'$pass'"'<br>
It took 'expr $middle - $start's to create and 'expr $end - $middle's to upload backup file, or 'expr $end - $start's at all.<br>
Have a nice day and check some statistic.<br>
<br>
Backup size: '$(du -h $BACKUPNAME | awk '{printf "%s",$1}')'.<br>
SHA256 of backup file: '$sha'.<br><br>
Space information: '$(megadf -u $megalogin -p $megapass -h)'.<br>' > $EMAILFILE
[ -s "$LOCKFILE" ] && echo "Other info: $(cat $LOCKFILE).<br>" >> $EMAILFILE
#echo "<br>">> $EMAILFILE

echo "$(date) - INFO - The backup process ($BACKUPNAME) finished. Backup size: $(du -h $BACKUPNAME | awk '{printf "%s",$1}'). It took `expr $middle - $start`s to create and `expr $end - $middle`s to upload backup file, or `expr $end - $start`s at all."

#send email with password
cat $EMAILFILE | /usr/sbin/sendmail $recipients
#cat $EMAILFILE

#remove temporary files
rm $LOCKFILE
rm $EMAILFILE

exit 0
