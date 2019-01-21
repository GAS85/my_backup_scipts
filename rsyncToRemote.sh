#!/bin/bash

SSHIdentityFile=/path/to/file/.ssh/id_rsa
SSHUser=user
WhereToMount=/mnt/remoteSystem

RemoteAddr=IP_or_host
RemoteBackupFolder=/path/to/backup

NexctCloudPath=/var/www/nextcloud/

# Folder and files to be excluded from backup.
# - data/updater* exclude updater backups and dowloads 
# - *.ocTransferId*.part exclude partly uploaded files
#
# This is reasonable "must have", everything below is just to save place:
#
# - data/appdata*/preview exclude Previews - they could be newle generated
# - data/*/files_trashbin/ exclude users trashbins
# - data/*/files_versions/ exclude users files Versions

excludeFromBackup="--exclude=data/updater*\
 --exclude=*.ocTransferId*.part\
 --exclude=data/appdata*/preview\
 --exclude=data/*/files_trashbin/\
 --exclude=data/*/files_versions/"

#########

if [ ! -d $WhereToMount ]; then
  mkdir -p $WhereToMount;
fi

echo Mount remote system
sshfs -o allow_other,default_permissions,IdentityFile=$SSHIdentityFile $SSHUser@RemoteAddr:RemoteBackupFolder $WhereToMount

echo Run Rsync without Preview, updater and transfer parts.
rsync -aP --no-o --no-g --delete $excludeFromBackup $NexctCloudPath $WhereToMount/nextcloud/

#rsync -aP --no-o --no-g --delete NexctCloudPath $WhereToMount/nextcloud/

echo Wait to finish sync
sleep 20

echo Unmount at the end
umount $WhereToMount

exit 0
