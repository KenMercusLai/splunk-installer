#!/bin/bash

# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
   echo "You need to be 'root'." 1>&2
   exit 1
fi

# determine which platform the script is running on, currently only support linux system
SYSTEM=$(uname -s)
if [[ $SYSTEM != *"Linux"* ]]; then
  echo "This script supports Linux systems ONLY."
  exit 1
fi

# determine which package type should download based on which distro is running on
# Ubuntu -> deb
# centos -> rpm
# others -> tgz
DISTRO=$(cat /etc/*-release)
PACKAGE_TYPE='tgz'
if [[ $DISTRO == *"Ubuntu"* ]]; then
  PACKAGE_TYPE='deb'
elif [[ $DISTRO == *"Debian"* ]]; then
  PACKAGE_TYPE='deb'
elif [[ $DISTRO == *"Centos"* ]]; then
  PACKAGE_TYPE='rpm'
fi

# determine whether dependencies are available
WGET = $(which wget)
CURL = $(which wget)

clear

export SPLUNK_HOME="/opt/splunk"
SPLUNK_BACKUP_DEFAULT_ETC="/var/opt/splunk"
# ARG DEBIAN_FRONTEND=noninteractive
SPLUNK_GROUP="splunk"
SPLUNK_USER="splunk"

# add splunk:splunk user
groupadd -r ${SPLUNK_GROUP} 
useradd -r -m -g ${SPLUNK_GROUP} ${SPLUNK_USER}

if [ $PACKAGE_TYPE == "deb" ] ; then
    # env setup
    ## make the "en_US.UTF-8" locale so splunk will be utf-8 enabled by default
    apt-get update
    apt-get install -y --no-install-recommends apt-utils dialog locales procps
    echo "LC_ALL=en_US.UTF-8" >> /etc/environment
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    locale-gen en_US.UTF-8
    export LANGUAGE="en_US.UTF-8"
    export LANG="en_US.UTF-8"

    ## install tools needed in the setup if necessary
    if [ -z "$WGET" ]; then
        apt-get install -y wget
    fi
    if [ -z "$CURL" ]; then
        apt-get install -y curl
    fi

    SPLUNK_URL=$(curl -s https://www.splunk.com/en_us/download/splunk-enterprise.html | grep -o "https[^\"]*.${PACKAGE_TYPE}" | head -n 1)
    SPLUNK_FILENAME=${SPLUNK_URL##*/}
    mkdir -p ${SPLUNK_HOME}
    wget -O /tmp/${SPLUNK_FILENAME} ${SPLUNK_URL}
    # cp /opt/test.deb /tmp/${SPLUNK_FILENAME}
    wget -O /tmp/${SPLUNK_FILENAME}.md5 ${SPLUNK_URL}.md5
    cd /tmp
    if [ "$(md5sum ${SPLUNK_FILENAME} | awk '{print $1}')" != "$(cat ${SPLUNK_FILENAME}.md5 | awk '{print $NF}')" ]; then
        echo "The MD5 of downloaded file is different from expected, please re-run the script to download it again."
        exit 1
    fi

    dpkg -i ${SPLUNK_FILENAME}

    ## post installation
    rm /tmp/${SPLUNK_FILENAME} 
    rm /tmp/${SPLUNK_FILENAME}.md5 
    mkdir -p /var/opt/splunk 
    cp -R ${SPLUNK_HOME}/etc ${SPLUNK_BACKUP_DEFAULT_ETC}
    echo "OPTIMISTIC_ABOUT_FILE_LOCKING=1" >> ${SPLUNK_HOME}/etc/splunk-launch.conf

    chown -R ${SPLUNK_USER}:${SPLUNK_GROUP} ${SPLUNK_HOME}
    chown -R ${SPLUNK_USER}:${SPLUNK_GROUP} ${SPLUNK_HOME}/etc
    chown -R ${SPLUNK_USER}:${SPLUNK_GROUP} ${SPLUNK_BACKUP_DEFAULT_ETC}
    # remove tools that used in the setup if necessary
    if [ -z "$WGET" ]; then
        apt-get purge -y --auto-remove wget
    fi
    if [ -z "$CURL" ]; then
        apt-get purge -y --auto-remove curl
    fi

    # filesystem locktest will fail on docker, it needs to be disabled on docker
    CONTROL_GROUPS=$(cat /proc/1/cgroup)
    if [[ $CONTROL_GROUPS == *"docker"* ]]; then
        echo "OPTIMISTIC_ABOUT_FILE_LOCKING = 1" >> ${SPLUNK_HOME}/etc/splunk-launch.conf
    fi

    ${SPLUNK_HOME}/bin/splunk enable boot-start --accept-license
    ${SPLUNK_HOME}/bin/splunk start #--accept-license
    
    # write variables to shell profile
    echo "export LANGUAGE=\"en_US.UTF-8\"
    export LANG=\"en_US.UTF-8\"
    export SPLUNK_HOME=/opt/splunk>>~/.bash_profile
fi
