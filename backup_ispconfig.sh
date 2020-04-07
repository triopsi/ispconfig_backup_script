#!/bin/bash
##########################################################################################
#  _____  _____ _____   _____             __ _         ____             _                
# |_   _|/ ____|  __ \ / ____|           / _(_)       |  _ \           | |               
#   | | | (___ | |__) | |     ___  _ __ | |_ _  __ _  | |_) | __ _  ___| | ___   _ _ __  
#   | |  \___ \|  ___/| |    / _ \| '_ \|  _| |/ _` | |  _ < / _` |/ __| |/ / | | | '_ \ 
#  _| |_ ____) | |    | |___| (_) | | | | | | | (_| | | |_) | (_| | (__|   <| |_| | |_) |
# |_____|_____/|_|     \_____\___/|_| |_|_| |_|\__, | |____/ \__,_|\___|_|\_\\__,_| .__/ 
#                                               __/ |                             | |    
#                                              |___/                              |_|    
# 1) copy the backup script on the ispconfig server
# 2) fill the db and sftp variable
# 3) make sure that the script have the right access (chmod 500)
# 4) create a crontab with root (crontab -u root -l)
#     e.g. every day on 4:30am -> 30  4  * * * /to/backup_ispconfig.sh > /dev/null 2>&1
#
# Structur
# BASE = root DB backups (root DB, ISPCOnfig DB and roundcube DB)
# databases = all client DB backups
# maildomains = all maildomain DB backups
# webdomains = all client websites backups
#
##########################################################################################
#mysqldump
SQLDUMP="/usr/bin/mysqldump"

#mysql
SQLBIN="/usr/bin/mysql"

#DB settings for the mysql-db
USER="root"								
PASS="#"	
MYHOST="localhost"

#like /var/backups no slash at the end!
BPATH="/var/backups"

#suffix backupfilename
DATUM=`date +'%Y-%m-%d'`	

#SFTP settings
# use sshpass
# make sure that sshpass is install
ActiveSFTP=0
SFTPUser=""
SFTPPass=""
SFTPHost=""
SFTPDirection=""

######################################################### MAIN ######################################################################
### Log-Funktionen:

function logInfo
{
  local ts
  ts="$(date +'%Y%m%d-%H%M%S%z')"
  echo "${ts} INFO $*"
}

function logWarn
{
  local ts
  ts="$(date +'%Y%m%d-%H%M%S%z')"
  echo "${ts} WARN $*"
}

function logErr
{
  local ts
  ts="$(date +'%Y%m%d-%H%M%S%z')"
  echo "${ts} ERROR $*"
  echo "${ts} ERROR $*" >&2
}

# Exit Function
function exit_bash ()
{
  local exitcode=$1
	if [ $exitcode -eq 0 ];then
		echo "Finisch RC=0"
	else
		logErr "Abbort RC=$1"
	fi
	DATE=`date '+%Y-%m-%d %H:%M:%S'`
	echo "End: $DATE "
	exit $1
}
DATEN=`date '+%Y-%m-%d %H:%M:%S'`
logInfo "Start: $DATEN"
logInfo "Exists backup directory \"$BPATH\"?"
if [ ! -d $BPATH ]
then
    logInfo "no - create it"
	  mkdir $BPATH
  else
    logInfo "yes"
fi

if [ ! -d $BPATH/BASE ]
then
	mkdir $BPATH/BASE
fi

if [ ! -d $BPATH/databases ]
then
	mkdir $BPATH/databases
fi

if [ ! -d $BPATH/maildomains ]
then
	mkdir $BPATH/maildomains
fi

if [ ! -d $BPATH/webdomains ]
then
	mkdir $BPATH/webdomains
fi

#clean up
logInfo "clean the backup directory. Find old files +3 days and delete this"
find $BPATH -type f -mtime +3 -exec rm {} \;
if [ $? -eq 0 ]
then
  logInfo "clean finished"
fi

logInfo "backup directions exists and are ready"
# Complete MySQL-DB-Dump 
#
logInfo "DB dump for all databases"
`$SQLDUMP -u$USER -p$PASS -h $MYHOST --all-databases --add-drop-table | gzip -9 > $BPATH/BASE/$DATUM'_BASE__'complete_MySQL-DB'.sql.gz'`
if [ $? -eq 0 ]
then
  logInfo "DB dump finished"
else
  logWarn "cannot dump"
fi

# ISPConfig-DB 
#
logInfo "DB dump for the ispconfig databases"
DBISPconfig="dbispconfig"
`$SQLDUMP -u$USER -p$PASS -h $MYHOST $DBISPconfig | gzip -9 > $BPATH/BASE/$DATUM'_BASE__'$DBISPconfig'.sql.gz'`
if [ $? -eq 0 ]
then
  logInfo "DB dump finished"
else
  logWarn "cannot dump"
fi

# Roundcubemail-DB 
#
logInfo "DB dump for the roundmail databases"
DBM="roundcubemail"
`$SQLDUMP -u$USER -p$PASS -h $MYHOST $DBM | gzip -9 > $BPATH/BASE/$DATUM'_BASE__'$DBM'.sql.gz'`
if [ $? -eq 0 ]
then
  logInfo "DB dump finished"
else
  logWarn "cannot dump"
fi

# Client databases 
#
logInfo "DB dump for all client databases"
$SQLBIN -u$USER -p$PASS dbispconfig -e "select database_name from web_database order by database_id asc;" | grep [a-zA-Z0-9] | grep -v 'database_name' |
while read DBNAME
do
  $SQLBIN -u$USER -p$PASS dbispconfig -e "SELECT CONCAT(c.username,'_',w.database_name) AS FILENAME FROM client c, web_database w WHERE w.sys_groupid = c.client_id+1 AND w.database_name = '$DBNAME';" | grep [a-zA-Z0-9] | grep -v 'FILENAME' |
  while read FILENAME
  do
    $SQLDUMP -u$USER -p$PASS -h $MYHOST $DBNAME | gzip -9 > $BPATH/databases/$DATUM'_client__'$FILENAME'.sql.gz'
    if [ $? -eq 0 ]
      then
        logInfo "DB dump for $FILENAME finished"
      else
        logWarn "cannot dump for $FILENAME"
      fi
  done
done

# Client maildomains
#
logInfo "File dump for all maildomains"
$SQLBIN -u$USER -p$PASS dbispconfig -e "SELECT domain AS MAILDOMAIN FROM mail_domain order by domain asc;" | grep [a-zA-Z0-9] | grep -v 'MAILDOMAIN' |
while read MAILDOMAIN
do
   tar czf $BPATH/maildomains/$DATUM'_mails__'$MAILDOMAIN'.tar.gz' /var/vmail/$MAILDOMAIN
   if [ $? -eq 0 ]
    then
      logInfo "File dump for $MAILDOMAIN finished"
    else
      logWarn "cannot dump for $MAILDOMAIN"
    fi
done


# Client websites
#
logInfo "File dump for all client websites"
$SQLBIN -u$USER -p$PASS dbispconfig -e "SELECT domain AS WEBSITE FROM mail_domain order by domain asc;" | grep [a-zA-Z0-9] | grep -v 'WEBSITE' |
while read WEBSITE
do
   tar czf $BPATH/webdomains/$DATUM'_website__'$WEBSITE'.tar.gz' /var/www/$WEBSITE
    if [ $? -eq 0 ]
    then
      logInfo "File dump for $WEBSITE finished"
    else
      logWarn "cannot dump for $WEBSITE"
    fi
done


#Backups put on backup server
if [ $ActiveSFTP -eq 1 ];then
logInfo "dumps put on backup server"
for i in $(find $BPATH -type f -name \*.tar.gz); do
sshpass -p $SFTPPass -e sftp -oBatchMode=no -b - $SFTPUser@$SFTPHost << !
cd $SFTPDirection
put $i
bye
!
done
if [ $? -eq 0 ]
then
  logInfo "dumps finished"
fi
fi

#Exit
exit_bash 0