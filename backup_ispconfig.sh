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

#options
roundcube=1
full_system=1

#DB settings for the mysql-db
USER="root"								
PASS=""	
MYHOST="localhost"

#like /var/backups no slash at the end!
BPATH="/backups/daten"

#suffix backupfilename
DATUM=`date +'%Y-%m-%d'`	

#SFTP settings
# use sshpass
# make sure that sshpass are installed
activeSFTP=0
SFTPUser=""
SFTPPass=""
SFTPHost=""
SFTPDirection=""

#Email notify
notifymail=0
mailto=""

#Xmpp notify
# use sendxmpp
# make sure that sendxmpp are installed
notifyxmpp=0
xmppusername=""
xmpppassword=""
xmppserver=""
xmppto=""

######################################################### MAIN ######################################################################
fail=0
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
	DATE=`date +'%Y-%m-%d %H:%M:%S'`
	echo "End: $DATE "
	exit $1
}
start_date=`date +'%Y-%m-%d %H:%M:%S'`
logInfo "Start: $start_date"
logInfo "Exists backup directory \"$BPATH\"?"
if [ ! -d $BPATH ]
then
    logInfo "no - create it"
	  mkdir $BPATH
  else
    logInfo "yes"
fi

if [ ! -d $BPATH/$DATUM ]
then
	mkdir $BPATH/$DATUM
fi

if [ ! -d $BPATH/$DATUM/BASE ]
then
	mkdir $BPATH/$DATUM/BASE
fi

if [ ! -d $BPATH/$DATUM/databases ]
then
	mkdir $BPATH/$DATUM/databases
fi

if [ ! -d $BPATH/$DATUM/maildomains ]
then
	mkdir $BPATH/$DATUM/maildomains
fi

if [ ! -d $BPATH/$DATUM/webdomains ]
then
	mkdir $BPATH/$DATUM/webdomains
fi

if [ ! -d $BPATH/$DATUM/system ] && [ $full_system -eq 1 ]
then
	mkdir $BPATH/$DATUM/system
fi

##
## clean up
##
logInfo "clean the backup directory. Find old files +3 days and delete this"
find $BPATH -type f -mtime +3
find $BPATH -type f -mtime +3 -exec rm -rf {} \;
if [ $? -eq 0 ]
then
  logInfo "clean finished"
fi
logInfo "backup directions exists and are ready"

##
## Complete MySQL-DB-Dump 
##
logInfo "DB dump for all databases"
`$SQLDUMP -u$USER -p$PASS -h $MYHOST --all-databases --add-drop-table | gzip -9 > $BPATH/$DATUM/BASE/$DATUM'_BASE__'complete_MySQL-DB'.sql.gz'`
if [ $? -eq 0 ]
then
  logInfo "DB dump finished"
else
  logWarn "cannot dump"
  fail=1
fi

##
## ISPConfig-DB 
##
logInfo "DB dump for the ispconfig databases"
DBISPconfig="dbispconfig"
`$SQLDUMP -u$USER -p$PASS -h $MYHOST $DBISPconfig | gzip -9 > $BPATH/$DATUM/BASE/$DATUM'_BASE__'$DBISPconfig'.sql.gz'`
if [ $? -eq 0 ]
then
  logInfo "DB dump finished"
else
  logWarn "cannot dump"
  fail=1
fi

##
## Roundcubemail-DB 
##
if [ $roundcube -eq 1 ];then
  logInfo "DB dump for the roundmail databases"
  DBM="roundcube"
  `$SQLDUMP -u$USER -p$PASS -h $MYHOST $DBM | gzip -9 > $BPATH/$DATUM/BASE/$DATUM'_BASE__'$DBM'.sql.gz'`
  if [ $? -eq 0 ]
  then
    logInfo "DB dump finished"
  else
    logWarn "cannot dump"
  fail=1
  fi
fi

##
## Client databases 
##
logInfo "DB dump for all client databases"
$SQLBIN -u$USER -p$PASS dbispconfig -e "select database_name from web_database order by database_id asc;" | grep [a-zA-Z0-9] | grep -v 'database_name' |
while read DBNAME
do
  $SQLBIN -u$USER -p$PASS dbispconfig -e "SELECT CONCAT(c.username,'_',w.database_name) AS FILENAME FROM client c, web_database w WHERE w.sys_groupid = c.client_id+1 AND w.database_name = '$DBNAME';" | grep [a-zA-Z0-9] | grep -v 'FILENAME' |
  while read FILENAME
  do
    $SQLDUMP -u$USER -p$PASS -h $MYHOST $DBNAME | gzip -9 > $BPATH/$DATUM/databases/$DATUM'_client__'$FILENAME'.sql.gz'
    if [ $? -eq 0 ]
      then
        logInfo "DB dump for $FILENAME finished"
      else
        logWarn "cannot dump for $FILENAME"
        fail=1
      fi
  done
done

##
## Client maildomains
##
logInfo "File dump for all maildomains"
$SQLBIN -u$USER -p$PASS dbispconfig -e "SELECT domain AS MAILDOMAIN FROM mail_domain order by domain asc;" | grep [a-zA-Z0-9] | grep -v 'MAILDOMAIN' |
while read MAILDOMAIN
do
  if [ -d /var/vmail/$MAILDOMAIN ];then
    tar czf $BPATH/$DATUM/maildomains/$DATUM'_mails__'$MAILDOMAIN'.tar.gz' /var/vmail/$MAILDOMAIN > /dev/null 2>&1
    if [ $? -eq 0 ]
      then
        logInfo "File dump for $MAILDOMAIN finished"
      else
        logWarn "cannot dump for $MAILDOMAIN"
        fail=1
      fi
  fi
done

##
## Client websites
##
logInfo "File dump for all client websites"
$SQLBIN -u$USER -p$PASS dbispconfig -e "SELECT domain AS WEBSITE FROM domain order by domain asc;" | grep [a-zA-Z0-9] | grep -v 'WEBSITE' |
while read WEBSITE
do
  if [ -d /var/www/$WEBSITE ];then
      tar chzf $BPATH/$DATUM/webdomains/$DATUM'_website__'$WEBSITE'.tar.gz' /var/www/$WEBSITE > /dev/null 2>&1
      if [ $? -eq 0 ]
      then
        logInfo "File dump for $WEBSITE finished"
      else
        logWarn "cannot dump for $WEBSITE"
        fail=1
      fi
  fi
done

##
# System backup
##
if [ $full_system -eq 1 ];then
##
## Create list of installed software
##
logInfo "create list of installed software"
dpkg --get-selections > $BPATH/$DATUM/system/$DATUM'_software.list'
if [ $? -eq 0 ]
  then
    logInfo "list of installed software are finished"
  else
    logWarn "cannot create a list of installed software"
    fail=1
  fi

##
## Create a full file backup
##
logInfo "System dump /root /etc /home /var/vmail /var/www /opt /var/lib /usr/local/ispconfig"
tar pczf $BPATH/$DATUM/system/$DATUM'_systems.tar.gz' /root /etc /home /var/vmail /var/www /opt /var/lib /usr/local/ispconfig > /dev/null 2>&1
if [ $? -eq 0 ]
  then
    logInfo "System dump finished"
  else
    logInfo "System dump with warn logs finished"
  fi
fi

##
## Backups put on backup server
##
if [ $activeSFTP -eq 1 ];then
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

GROESSE_BACKUP="$(du -sh $BPATH/$DATUM)"
ENDZEIT=`date +'%Y-%m-%d %H:%M:%S'`

##
## Send a notify via mail
##
if [ $notifymail -eq 1 ];then
logInfo "send a notify vie email"
if [ $fail -eq 0 ];then
mail -s "Backup war erfolgreich" "${mailto}"  <<EOM
  Hallo Admin,
  das Backup wurde erfolgreich erstellt.

  ----------------Details--------------------
  Datum:          ${DATUM}
  Startzeit:      ${start_date}
  Endzeit:        ${ENDZEIT}
  Dateigroesse
  * Systembackup:   ${GROESSE_BACKUP}
  ----------------ENDE-----------------------
EOM
else
mail -s "Backup war fehlerhaft!" "${mailto}"  <<EOM
Hallo Admin,
das Backup am ${DATUM} wurde mit Fehler(n) beendet.
EOM
fi
logInfo "finisched"
fi

##
## Send a notify via xmpp
##
if [ $notifyxmpp -eq 1 ];then
  logInfo "send a notify vie xmpp"
  if [ $fail -eq 0 ];then
    echo -e "Hallo Admin,\ndas Backup wurde erfolgreich erstellt.\n\nGesamtgroesse:\t${GROESSE_BACKUP}" | /usr/bin/sendxmpp -u "$xmppusername" -j "$xmppserver" -p "$xmpppassword" -s "Backup Script" -v -i -t $xmppto
  else
    echo -e "Hallo Admin,\ndas Backup war fehlerhaft.\nBitte in den Logs schauen." | /usr/bin/sendxmpp -u "$xmppusername" -j "$xmppserver" -p "$xmpppassword" -s "Backup Script" -v -i -t $xmppto
  fi
logInfo "finisched"
fi

#Exit
exit_bash 0