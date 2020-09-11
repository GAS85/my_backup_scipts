#!/bin/bash

# By Georgiy Sitnikov.
#
# Will do system backup and upload encrypted to mega - NEEDS megatools
#
# AS-IS without any warranty
#
# Supported key --upload to upload latest files instead of do backup again

# https://help.nextcloud.com/t/nextcloud-backup-and-restore/51589/6

nonce=$(md5sum <<< $(ip route get 8.8.8.8 | awk '{print $NF; exit}')$(hostname) | cut -c1-5 )

# Please do not use root folder
WORKINGDIR=/var/backups
toBackup="/"

configFile="/etc/restic-systembackup.conf"

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
 --exclude=/home/*/.cache\
 --exclude=/home/*/.local/share/Trash"

# Check if you set custom config File location
if [ ! -z "$1" ]; then

	configFile="$1"
	nonce=$(md5sum $configFile | cut -c1-5 )

fi

LOCKFILE=/tmp/restic-backup-$nonce

if [ -f "$LOCKFILE" ]; then

	# Remove lock file if script fails last time and did not run longer than 5 days due to lock file.
	find "$LOCKFILE" -mtime +5 -type f -delete
	echo "$(date) - WARNING - Another instance blocked backup process."
	exit 1

fi

if [ ! -f "$configFile" ]; then

	echo "$(date) - ERROR - Config file was not found under $configFile. Will continuer with default settings."

else

	if [ ! -r "$configFile" ]; then

		echo "$(date) - ERROR - Config file could not be read."
		exit 1

	fi

fi

source "$configFile"

#Check if Working dir exist
if [ ! -d "$WORKINGDIR" ]; then

	echo "$(date) - Directory $WORKINGDIR does not exist"
	exit 1

fi

touch $LOCKFILE

cd $WORKINGDIR
# unlock restic
restic unlock

#do backup
restic -r $WORKINGDIR backup $toBackup $excludeFromBackup --one-file-system

# clean up backup dir. As per https://restic.readthedocs.io/en/stable/060_forget.html?highlight=keep-#removing-snapshots-according-to-a-policy
restic forget --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --keep-yearly 75

restic prune

# upload to cloud
rclone sync $WORKINGDIR $remote:$folder

# upload to another cloud if set
if [ ! -z "$remote2" ]; then

	rclone sync $WORKINGDIR $remote2:$folder2

fi

rm $LOCKFILE

exit 0
