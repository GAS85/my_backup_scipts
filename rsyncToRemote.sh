#!/bin/bash

# By Georgiy Sitnikov.
#
# Will do NC backup and upload to remote server via SSH with key authentication
#
# AS-IS without any warranty

SSHIdentityFile=/path/to/file/.ssh/id_rsa
SSHUser=user
RemoteAddr=IP_or_host
RemoteBackupFolder=/path/to/backup
NextCloudPath=/var/www/nextcloud/

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

# Check if config.php exist
[[ -e $NextCloudPath/config/config.php ]] || { echo >&2 "Error - сonfig.php could not be found under "$NextCloudPath"/config/config.php. Please check the path"; exit 1; }

# Fetch data directory place from the config file
DataDirectory=$(grep datadirectory $NextCloudPath/config/config.php | cut -d "'" -f4)

echo Run Rsync of NC root folder.
rsync -aP --no-o --no-g --delete --exclude=data --exclude=$DataDirectory -e "ssh -i $SSHIdentityFile" $NextCloudPath $SSHUser@$RemoteAddr:$RemoteBackupFolder/nextcloud/

echo Run Rsync of NC Data folder.
rsync -aP --no-o --no-g --delete $excludeFromBackup -e "ssh -i $SSHIdentityFile" $NextCloudPath $SSHUser@$RemoteAddr:$RemoteBackupFolder/nextcloud/

echo Ready.
exit 0
