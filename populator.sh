## Tool to do test activities against a file system
## Experimental/educational purposes
##
## Get constantly updating, expanding, and drifting content
## designed/intended to always scale to the maximum size of
## a disk/file system...
## It's basic design if ran off of serveral 'generator' hosts 
## can be complementary and work in tandem; their actions 
## ought to be complementary, or at worst not overly get into 
## each others' way. 
##
## Author: Joe Szilagyi
## Version: 0.03 / 10-26-2017

####################
### to-do /ideas ###
####################

# note - not yet set up to actually work with a cluster
# right now it just spins up traffic/noise locally
#
# storage access test - network, is it up?
# mount point / nfs test, is it accessible?
# nfs testing - can we read/write
#
# initial assumptions: just cron all the thing(s)
# run multiple instances of populate.sh? Use ps to limit max number at $x ?
# integrate sequence.sh for what do with individual file activities
# multi threading
# distributed system(s)
# integrate/roll logging up into a central system if distributed

# begin

#!/bin/bash

#####################
### key variables ###
#####################

### system variables / cluster variables
primarystorage=/dev/sda1

### tool variables ###
toolname=POPULATOR #for logging, and in case we ever rename this
usercount=50 #defines the minimum number of users to iterate in functions
usernameprefix=User #what comes before the user_count number, e.g. User#
minimumfilecount=100 # minimum number of files in a user's top directory
storagebase=/home/ifs #defines base level of storage location
logfiledir=/var/log #defines our base log file directory
logfile=$logfiledir/populator.log
maxlogsize=4294967292 #max size of our log file before rotation
maxdiskusage=10 # represented as percentage of df output
#maxdiskusage=6 # represented as percentage of df output // tiny number for testing cull function
### fixed values / don't edit ###
filemanifestfile=/tmp/filemanifest.txt # used for when we do disk capacity clean-up
directorymanifesfile=/tmp/directorymanifest.txt # used for when we do disk capacity clean-up






##########################
##### jobs/functions #####
##########################

#### How many instances of populate.sh are running?
## keep it simple for now; if already running, abort
function is_populate_running {
echo "is_populate_running"
is_this_on=`ps auxw|grep populate.sh|grep -v grep|wc -l`
if [ $is_this_on -gt 3 ]; then # is there more than 1 instance running? Abort if so!
  echo "$toolname `date +"%m-%d-%Y %T"` WARNING $toolname is already running per ps output ($is_this_on instances). Aborting new instance of $toolname." >> $logfile
  exit 0;
fi
unset is_this_on
}

#### Does our structure of things exist?
## does each user's directory and other key directory structure exist?
## this pathing is basic/temp/local until we can tie this into a nice
## proper Isilon cluster. This is for local experiments/design.
function check_basefolders_exist {
echo "check_basefolders_exist"
if [ ! -d "$storagebase" ]; then
  mkdir $storagebase
  echo "$toolname `date +"%m-%d-%Y %T"` ERROR storagebase: $storagebase not found, attempting to create." >> $logfile
  echo "$toolname `date +"%m-%d-%Y %T"` ERROR logfiledir: $logfiledir not found, attempting to create." >> $logfile
fi
if [ ! -d "$storagebase" ]; then
  echo "CRITICAL! Unable to create or access $storagebase -- $toolname is aborting at `date +"%m-%d-%Y %T"`" >> $logfile
fi
if [ ! -d "$logfiledir" ]; then
  echo "CRITICAL! Unable to access $logfiledir -- $toolname is aborting at `date +"%m-%d-%Y %T"`"
fi
}

function check_userfolders_exist {
echo "check_userfolders_exist"
for user in $(eval echo {1..$usercount});
do
  if [ ! -d "$storagebase/$usernameprefix$user" ]; then
    echo "$toolname `date +"%m-%d-%Y %T"` ERROR missing user directory: $storagebase/$usernameprefix$user not found, attempting to create." >> $logfile;
    mkdir /$storagebase/$usernameprefix$user;
  fi
done
}

## does the log file exist? is the ad hoc log file too big? time to rotate?
function checklogfilesize {
echo "checklogfilesize"
touch $logfile # ensure the existence of the file at minimum
logsize=$(du -b $logfile | awk '{print $1}');
if [ "$logsize" -gt "$maxlogsize" ] ; then #is the log file bigger than 1gb?
  echo "$toolname `date +"%m-%d-%Y %T"` WARNING log size: $logfile is greater than 1gb, attempting to rotate." >> $logfile
  if [ -f "$logfile.1.gz" ]; then #if the .1 log exists rotate
    echo "$toolname `date +"%m-%d-%Y %T"` WARNING log size: $logfile.1.gz exists, rotating to $logfile.2.gz; keeping two old logs." >> $logfile
    mv -f $logfile.1.gz $logfile.2.gz #lose the old .2; syslogd this later if time, otherwise eh
  fi
  mv $logfile $logfile.1 # rotate the log
  gzip $logfile.1 ; # zip our last log
  echo "$toolname `date +"%m-%d-%Y %T"` WARNING log size: $logfile rotation done; keeping two old logs." >> $logfile
fi
}


### Do our users have any files at all, or just empty directories?
### if so let's make a starter set of stuff
function check_userfolders_empty { #basically making sure there's *something* in the user folders
echo "check_userfolders_empty"
for user in $(eval echo {1..$usercount}); do #cycle through all expected users
  filesindir=`find $storagebase/$usernameprefix$user -type f|wc -l`; #how many files in their home dir?
  if [ "$filesindir" -lt "$minimumfilecount" ] ; then #if it's less than $minimumfilecount take action
    echo "$toolname `date +"%m-%d-%Y %T"` WARNING $storagebase/$usernameprefix$user is below $minimumfilecount objects! Proceeding to add/update starter content." >> $logfile
      # log that we fed the user
    for starterfilenumber in $(eval echo {1..$minimumfilecount}); do
      starterfilelines=`echo $((1 + RANDOM % 500))`;
        #set to 100 at base, can be anything, but this is fine
        #this is the maximum number of lines randomly set in new starter files
      head -$starterfilelines /dev/urandom > $storagebase/$usernameprefix$user/$usernameprefix$user.$starterfilenumber.file;
        #create their random trash content (its all arbitrary) out of urandom
      unset starterfilelines; #unset the var for the next cycle/user
    done;
  fi;
done
}


### DISK QUOTAS TESTING AND PROTECTION
### Are we under our maximum disk quota? If not, let's delete the oldest files until compliant.
# Find & sort files by age in the data storage directory scheme, to enact deletion of
# oldest modified files (oldest to newest) until we're in compliance with our max disk
# usage policy. Find command to find, while loop, while over policy, cull till compliant.

function is_system_over_quota { #basically making sure there's *something* in the user folders
echo "is_system_over_quota"
currentdiskusage=`df -h|grep $primarystorage|awk '{print $5}'|sed s/"%"//g`

## run the while true loop to deal with it
while [ $currentdiskusage -gt $maxdiskusage ]
  do
    find $storagebase -type f -printf "%T+\t%p\n" | sort -r|awk '{print $2}'|head -1000|grep -v deletemanifest > $storagebase/deletemanifest.txt # find the oldest files we got
    for deleted in `cat $storagebase/deletemanifest.txt`; do # delete 1000 at a time
      echo "$toolname `date +"%m-%d-%Y %T"` WARNING QUOTA Deleting $deleted under $storagebase to fix quota issues." >> $logfile
      rm -f $deleted;
  done
  rm -f $storagebase/deletemanifest.txt
done
}


####################################################
#### FILE MANAGEMENT & UPDATING SEQUENCE / TEST ####
####################################################

# define the actual functions of what each of them is
# here. The filesequence function afterward will then
# actually run these in place of the current "echo"
# placeholder, to actually do things to our filesystem.

#### GENERATE A FILE & DIRECTORY MANIFEST
# Create a temporary manifest of what we've got;
# update only if the manifest is older than an hour
# use this to reduce number of needed searches/find's
# on what we want to do; it's our cache of file names
# we may have some discrepencies - moved/deleted files etc.
filemanifest() {
echo "filemanifest"
if [ -f $storagebase/$filemanifestfile ]; then # does the manifest exist?
    if test "`find $filemanifestfile -mmin +10`"; then # is over 10 minutes old? Then regenerate.
      # then update it
      find $storagebase -type f -printf "%T+\t%p\n"|awk '{print $2}'|grep $usernameprefix > $filemanifestfile
    fi
  else # generate the file manifest
    find $storagebase -type f -printf "%T+\t%p\n"|awk '{print $2}'|grep $usernameprefix > $filemanifestfile
fi
}
directorymanifest() {
echo "directorymanifest"
if [ -f $directorymanifesfile ]; then # does the manifest exist?
    if test "`find $directorymanifesfile -mmin +10`"; then # is over 10 minutes old? Then regenerate.
      # then update it
      find $storagebase -type d -printf "%T+\t%p\n"|awk '{print $2}'|grep $usernameprefix > $directorymanifesfile
    fi
  else # generate the file manifest
    find $storagebase -type d -printf "%T+\t%p\n"|awk '{print $2}'|grep $usernameprefix > $directorymanifesfile
fi
}

# this will be our core sequence test; what do we do with a random file?
# first draft
filesequence()  {
echo "filesequence"
dice_things_to_do=`shuf -i 1-500 -n 1` # how many things to do?
for things_to_do in $(eval echo {1..$dice_things_to_do}); do # do one file action vs each hit/request
  dice_what_to_do=`shuf -i 1-100 -n 1` # odds, 1% to 100%; we'll do *something* each cycle
  # against a random set of 1 - $x files under $storagebase / or make new one

  if [ $dice_what_to_do -ge 1 -a $dice_what_to_do -le 42 ]; then # run create file function
   echo "SEQUENCE: create file"
    newfiledir=`shuf $directorymanifesfile| head -1`
    newfilename=`date|md5sum|awk '{print $1}'`
    newfile=$newfiledir/$newfilename.file
    newfilelines=`echo $((1 + RANDOM % 500))`;
    head -$newfilelines /dev/urandom > $newfile;
    echo "$toolname `date +"%m-%d-%Y %T"` CREATE $newfile" >> $logfile

  elif [ $dice_what_to_do -ge 43 -a $dice_what_to_do -le 45 ]; then # run create subdirectory function
    echo "SEQUENCE: create a new subdirectory"
    newdirparent=`shuf $directorymanifesfile| head -1`
    newdirname=`date|md5sum|awk '{print $1}'`
    newdir=$newdirparent/$newdirname.dir
    mkdir $newdir
    echo "$toolname `date +"%m-%d-%Y %T"` CREATE $newdir" >> $logfile

  elif [ $dice_what_to_do -ge 46 -a $dice_what_to_do -le 86 ]; then # run append file function
    echo "SEQUENCE: append to file"
    appendfileid=`shuf $filemanifestfile| head -1`
    appendfilelines=`echo $((1 + RANDOM % 500))`;
    head -$appendfilelines /dev/urandom >> $appendfileid;
    echo "$toolname `date +"%m-%d-%Y %T"` APPEND to $appendfileid" >> $logfile

  elif [ $dice_what_to_do -ge 87 -a $dice_what_to_do -le 90 ]; then # run copy something function
    copydice=`shuf -i 1-100 -n 1`
    if [ $copydice -ge 1 -a $copydice -le 97 ]; then # copy a file
        echo "SEQUENCE: copy a file"
        copyfileid=`shuf $filemanifestfile| head -1`
        copydirtargetid=`shuf $directorymanifesfile| head -1`
        cp -a $copyfileid $copydirtargetid
        echo "$toolname `date +"%m-%d-%Y %T"` COPY $copyfileid to $copydirtargetid" >> $logfile
      elif [ $copydice -ge 98 -a $copydice -le 100 ]; then # copy a directory whole
        echo "SEQUENCE: copy a directory"
        copydirid=`shuf $directorymanifesfile| head -1`
        copydirtargetid=`shuf $directorymanifesfile| head -1`
        cp -a $copydirid $copydirtargetid
        echo "$toolname `date +"%m-%d-%Y %T"` COPY $copydirid to $copydirtargetid" >> $logfile
    fi

  elif [ $dice_what_to_do -ge 91 -a $dice_what_to_do -le 98 ]; then # run move something function
    movedice=`shuf -i 1-100 -n 1`
    if [ $movedice -ge 1 -a $movedice -le 95 ]; then # move a file
        echo "SEQUENCE: move a file"
        movefileid=`shuf $filemanifestfile| head -1`
        movedirtargetid=`shuf $directorymanifesfile| head -1`
        mv -f $movefileid $movedirtargetid
        echo "$toolname `date +"%m-%d-%Y %T"` MOVE $movefileid to $movedirtargetid" >> $logfile
      elif [ $copydice -ge 96 -a $copydice -le 100 ]; then # move a directory whole
        echo "SEQUENCE: move a directory"
        movedirid=`shuf $directorymanifesfile| head -1`
        movedirtargetid=`shuf $directorymanifesfile| head -1`
        mv -a $movedirid $copydirtargetid
        echo "$toolname `date +"%m-%d-%Y %T"` MOVE $movedirid to $movedirtargetid" >> $logfile
    fi

  elif [ $dice_what_to_do -ge 99 -a $dice_what_to_do -le 100 ]; then # run delete something function
    deletedice=`shuf -i 1-100 -n 1`
    if [ $deletedice -ge 1 -a $deletedice -le 98 ]; then # move a file
     echo "SEQUENCE: delete a file"
        deletefileid=`shuf $filemanifestfile| head -1`
        rm $deletefileid
        echo "$toolname `date +"%m-%d-%Y %T"` DELETE file - $deletefileid" >> $logfile
      elif [ $deletedice -ge 99 -a $deletedice -le 100 ]; then # move a directory whole
        echo "SEQUENCE: delete a directory"
        deletedirid=`shuf $directorymanifesfile| grep ".dir"|head -1` # grep .dir; exclude User* top level
        rm -rf $deletedirid
        echo "$toolname `date +"%m-%d-%Y %T"` DELETE directory - $deletedirid" >> $logfile
    fi

  fi
  unset dice_what_to_do

done
unset dice_things_to_do
}


####################
### RUN THE TOOL ###
####################


## lets do it; leeeroy
is_populate_running; # is the tool already running one instance? if so abort!
check_basefolders_exist; # does our base structure exist?
check_userfolders_exist; # does our underlying user folder structure exist?
checklogfilesize; # are the log files too big?
is_system_over_quota; # how are we on system disk space? Fix it if over quota?
check_userfolders_empty; # check to see if we need a starter set of data in the user folders?
filemanifest; # have we got a 1> hour old manifest? Update if older than 5 minutes
directorymanifest; # have we got a 1> hour old manifest? Update if older than 5 minutes
filesequence; # make stuff happen / work the file storage





exit 0  
