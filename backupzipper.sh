#!/bin/bash

# By Georgiy Sitnikov.
# Will zip and encrypt backup of your MySQL DB and Cacti rrds
# MySQL Backup should be done separatly, or uncommented here as option.
# AS-IS without any warranty

mysql_backup=false
inline=false
SavePasswordLocal=true
mega_enable=false

. /etc/backupzipper.conf

if [ ! -f "/etc/backupzipper.conf" ]; then
	echo "$(date) - ERROR - Config file was not found under /etc/systembackup.conf. Exiting."
    exit 1
else
	if [ ! -r "/etc/backupzipper.conf" ]; then
		echo "$(date) - ERROR - Config file could not be read."
		exit 1
	fi
fi

nonce=$(md5sum <<< $(ip route get 8.8.8.8 | awk '{print $NF; exit}')$(hostname) | cut -c1-5 )
BACKUPNAME=backup-$(date +"%Y-%m-%d")_$nonce.gpg
LOCKFILE=/tmp/zipping_$nonce
EMAILFILE=/tmp/zipping_$nonce.email

#dbuser="root"
#dbpass="yyyy"
#Check if Backup file name already taken
if [ -f "$BACKUPNAME" ]; then
	# Added time to Backup name
	echo "$(date) - WARNING - Backup file $BACKUPNAME exist, will take another name (add time stamp) to create backup."
	BACKUPNAME=backup-$(date +"%Y-%m-%d_%T")_$(md5sum <<< $(ip route get 8.8.8.8 | awk '{print $NF; exit}')$(hostname) | cut -c1-5 ).gpg
fi

#ToFind="$(echo $BACKUPNAME | cut -c1-6)*$(md5sum <<< $(ip route get 8.8.8.8 | awk '{print $NF; exit}')$(hostname) | cut -c1-5 ).gpg"
#ToFind="$(echo $BACKUPNAME | cut -c1-6)*$(echo $BACKUPNAME | sed 's/.*\(...\)/\1/')"

if [ -f "$LOCKFILE" ]; then
	# Remove lock file if script fails last time and did not run longer than 2 days due to lock file.
	find "$LOCKFILE" -mtime +2 -type f -delete
	echo "$(date) - Warning - process is running"
	exit 1
fi

#Check if Working dir exist
if [ ! -d "$WORKINGDIR" ]; then
	echo "$(date) - ERROR - Directory $WORKINGDIR does not exist"
	exit 1
fi

touch $LOCKFILE
touch $EMAILFILE

# Put output to Logfile and Errors to Lockfile as per https://stackoverflow.com/questions/18460186/writing-outputs-to-log-file-and-console
exec 3>&1 1>>${LOCKFILE} 2>>${LOCKFILE}

if [ "$mysql_backup" == true ]; then
	#MySQL all DB backup and gzip if needed
	mysqldump --all-databases --single-transaction -u $dbuser -p$dbpass > $WORKINGDIR/tmp/all_databases.sql
	#mysqldump –all-databases | tar -czvf > $WORKINGDIR/backup-$(date +"%Y-%m-%d").sql.tgz
fi

#To Restore any DB
#mysql -u root -p
#CREATE DATABASE nextcloud;
#GRANT ALL ON nextcloud.* to 'nextcloud'@'localhost' IDENTIFIED BY 'set_database_password';
#FLUSH PRIVILEGES;
#exit
#mysql -u [username] -p[password] [db_name] < nextcloud-sqlbkp.bak

#Random password
pass="$(gpg --armor --gen-random 1 48)"

#Cacti Backup -- http://lifein0and1.com/2008/05/15/migrating-cacti-from-one-server-to-another/

#This is cacti working dir
cd $CACTIrraDIR

for entry in *.rrd
do
        rrdtool dump "$entry" > "$entry".xml
done

#tar -cvf $WORKINGDIR/tmp/rrd.tar *.rrd.xml
tar -czf $WORKINGDIR/rrd.tgz *.rrd.xml
rm *.rrd.xml

#put cacti pictures
tar -czf $WORKINGDIR/cacti_graphs.tgz $ATTACHDIR/*.png

#end Cacti backup

#to restore Cacti RRDs
#copy xml into /var/lib/cacti/rra/
#ls -1 *.rrd.xml | sed 's/\.xml//' | awk '{print "rrdtool restore "$1".xml "$1}' | sh -x
#chown www-data:www-data *.rrd

cd $WORKINGDIR

#GPG with password from above
tar -cz *gz | gpg --passphrase "$pass" --symmetric --no-tty -o $BACKUPNAME

#Upload to Mega
#megaput --no-progress --path /Root/Backup $BACKUPNAME >>$LOCKFILE
#megaput -u $megalogin -p $megapass --no-progress --path /Root/Backup $BACKUPNAME 2>>$LOCKFILE
#megaput -u $megalogin -p $megapass --path /Root/Backup $BACKUPNAME 2>>$LOCKFILE

if [ "$mega_enable" = true ]; then
	upload_command="megaput -u $megalogin -p $megapass --path /Root/Backup $BACKUPNAME"

	NEXT_WAIT_TIME=10
	until $upload_command || [ $NEXT_WAIT_TIME -eq 4 ]; do
		sleep $(( NEXT_WAIT_TIME++ ))
		echo "$(date) - ERROR - Mega Upload was failed, will retry after 10 seconds ($BACKUPNAME)."
	done
fi

#delete local old backups
# +15 is older than 15 days
#find "$ToFind" -mtime +15 -exec rm {} \; 2>>$LOCKFILE
find backup*gpg -mtime +15 -exec rm {} \; 2>>$LOCKFILE

#Email Header
echo "To: $recipients" > $EMAILFILE
echo "FROM: $from" >> $EMAILFILE
echo "Subject: $subject" >> $EMAILFILE
echo "MIME-Version: 1.0" >> $EMAILFILE
echo 'Content-Type: multipart/mixed; boundary="-q1w2e3r4t5"' >> $EMAILFILE
echo >> $EMAILFILE
echo '---q1w2e3r4t5' >> $EMAILFILE
echo "Content-Type: text/html" >> $EMAILFILE
echo "Content-Disposition: inline" >> $EMAILFILE
echo "" >> $EMAILFILE
echo 'The backup was created with password: '"'$pass'"'<br>' >> $EMAILFILE
echo "Have a nice day and check some statistic.<br>">> $EMAILFILE
echo "<br>">> $EMAILFILE
echo "Backup size: $(du -h $BACKUPNAME | awk '{printf "%s",$1}').<br>" >> $EMAILFILE
echo "MD5 of Backup file: $(md5sum $BACKUPNAME | awk '{printf "%s",$1}' | tr 'a-z' 'A-Z').<br>" >> $EMAILFILE
echo "Space information: $(megadf -u $megalogin -p $megapass -h).<br>" >> $EMAILFILE
[ -s "$LOCKFILE" ] && echo "Other info: $(cat $LOCKFILE).<br>" >> $EMAILFILE
echo "" >> $EMAILFILE

#
# So make man inline file with base64 or uuencode. uuencode will not be read by some programms
#
#echo '---q1w2e3r4t5'
#echo 'Content-Type: image/png; name='$(basename $ATTACH)''
##echo "Content-Transfer-Encoding: uuencode"
#echo "Content-Transfer-Encoding: base64"
#echo 'Content-Disposition: inline; filename='$(basename $ATTACH)''
#echo "Content-ID: <$(basename $ATTACH)>"
#echo '---q1w2e3r4t5--'
#base64 $ATTACH
#uuencode $ATTACH $(basename $ATTACH)
#
# #######################
#
# so make man attachment file with uuencode or base64.
#
##echo '---q1w2e3r4t5'
##echo 'Content-Type: application; name="'$(basename $ATTACH)'"'
##echo "Content-Transfer-Encoding: uuencode"
###echo "Content-Transfer-Encoding: base64"
##echo 'Content-Disposition: attachment; filename="'$(basename $ATTACH)'"'
##echo '---q1w2e3r4t5--'
###base64 $ATTACH
##uuencode $ATTACH $(basename $ATTACH)
#echo '---q1w2e3r4t5'
#echo 'Content-Type: image/png; name='$(basename $ATTACH1)''
#echo "Content-Transfer-Encoding: base64"
#echo 'Content-Disposition: inline; filename='$(basename $ATTACH1)''
#echo "Content-ID: <$(basename $ATTACH1)>"
#echo '---q1w2e3r4t5--'

if [ "$inline" == true ]; then

	for entry in "$ATTACHDIR"/graph_*_1.png
	do
		export ATTACH=$entry
		echo '---q1w2e3r4t5'
		echo 'Content-Type: image/png; name='$(basename $ATTACH)''
		echo "Content-Transfer-Encoding: uuencode"
		echo "Content-Transfer-Encoding: base64"
		echo 'Content-Disposition: inline; filename='$(basename $ATTACH)''
		echo "Content-ID: <$(basename $ATTACH)>"
		echo '---q1w2e3r4t5--'
		base64 $ATTACH
		uuencode $ATTACH $(basename $ATTACH)
	done

else

	for entry in "$ATTACHDIR"/graph_*_1.png
	do
		export ATTACH=$entry
		echo '<img src="'$(basename $ATTACH)'" alt="''" />' >> $EMAILFILE
		echo '---q1w2e3r4t5' >> $EMAILFILE
		echo 'Content-Type: image/png; name='$(basename $ATTACH)'' >> $EMAILFILE
		echo "Content-Transfer-Encoding: base64" >> $EMAILFILE
		echo 'Content-Disposition: inline; filename='$(basename $ATTACH)'' >> $EMAILFILE
		echo "Content-ID: <$(basename $ATTACH)>" >> $EMAILFILE
		echo '' >> $EMAILFILE
		base64 $ATTACH >> $EMAILFILE
	done
fi

#send email with password and attachments
$Sendmail $recipients < $EMAILFILE

#remove temporary files
rm $LOCKFILE
rm $EMAILFILE

# Opt: save password locally if Email fails, or you do not want to send it.
if [ "$SavePasswordLocal" == true ]; then
	echo "$(date) - The backup ($BACKUPNAME) was created with password: $pass - MD5 of backup file: $(md5sum $BACKUPNAME | awk '{printf "%s",$1}' | tr 'a-z' 'A-Z')" >> $WORKINGDIR/passes.txt
fi

exit 0
