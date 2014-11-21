#!/usr/bin/env bash

# OS VERSION: Ubuntu Server 12.04 LTS and 14.04 LTS
# ARCH: x32_64

Loreji_GitHubVersion=1.0.0

# Official Loreji Automated Installation Script
# =============================================
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Display the 'welcome' splash/user warning info..
echo -e "\n#####################################################"
echo "#   Welcome to the Official Loreji Installer for   #"
echo "#     Ubuntu server and Debian Server      #"
echo "#####################################################"
echo -e "\nChecking that minimal requirements are ok"

# Check if the user is 'root' before allowing installation to commence
if [ $UID -ne 0 ]; then
    echo "Install failed: you must be logged in as 'root' to install."
    echo "Use command 'sudo -i', then enter root password and then try again."
    exit 1
fi

# Ensure the OS is compatible with the launcher
BITS=$(uname -m | sed 's/x86_//;s/i[3-6]86/32/')
if [ -f /etc/lsb-release ]; then
  OS=$(grep DISTRIB_ID /etc/lsb-release | sed 's/^.*=//')
  VER=$(grep DISTRIB_RELEASE /etc/lsb-release | sed 's/^.*=//')
else
  OS=$(uname -s)
  VER=$(uname -r)
fi
echo "Detected : $OS  $VER  $BITS"

# Check for some common control panels that we know will affect the installation/operating of Loreji.
if [ -e /usr/local/cpanel ] || [ -e /etc/loreji ] || [ -e /usr/local/directadmin ] || [ -e /usr/local/solusvm/www ] || [ -e /usr/local/home/admispconfig ] || [ -e /usr/local/lxlabs/kloxo ] ; then
    echo "It appears that a control panel is already installed on your server; This installer "
    echo "is designed to install and configure Loreji on a clean OS installation only!"
    echo -e "\nPlease re-install your OS before attempting to install using this script."
    exit 1;
fi

inst() {
    dpkg -l "$1" 2> /dev/null | grep '^ii' &> /dev/null
}

# Check for some common packages that we know will affect the installation/operating of Loreji.
# We expect a clean OS so no apache/mySQL/bind/postfix/php!
if (inst php) || (inst apache) || (inst mysql) || (inst postfix) || (inst dovecot) ; then
    echo "It appears that apache/mysql/bind/postfix is already installed; This installer "
    echo "is designed to install and configure Loreji on a clean OS installation only!"
    echo -e "\nPlease re-install your OS before attempting to install using this script."
    exit 1;
fi

# ***************************************
# Prepare or query informations required to install

# Propose selection list for the time zone
echo "Preparing to select timezone, please wait a few seconds..."
apt-get -yqq update &>/dev/null
apt-get -yqq install tzdata &>/dev/null
dpkg-reconfigure tzdata
tz=$(cat /etc/timezone)

# Installer options
apt-get -yqq install dnsutils
echo "You will be asked for the FQDN that will be used to access Loreji on your server"
echo "- It MUST be a sub-domain of you main domain, it must NOT be your main domain only. Example: panel.yourdomain.com"
echo "- It MUST be already setup in your DNS nameserver (and propagated)."
fqdn=$(/bin/hostname)
while true; do
    read -e -p "FQDN for Loreji: " -i "$fqdn" fqdn
    sub=$(echo "$fqdn" | sed -n 's|\(.*\)\..*\..*|\1|p')
    if [[ "$sub" == "" ]]; then
        echo "The FQDN must be a subdomain."
    else
        dnsip=$(host "$fqdn"|grep address|cut -d" " -f4)
        if [[ "$dnsip" == "" ]]; then
            echo "The subdomain $fqdn have no IP assigned in DNS"
	    echo "You must add a A record in the DNS manager for this subdomain"
	    echo "  and then wait until propagation is done."
	    echo "For more information, take a look at http://loreji.com"
        else
            publicip=$(wget -qO- https://loreji.com/api/ip)
            read -e -p "Enter the public (external) server IP: " -i "$publicip" publicip
            if [[ "$publicip" == "$dnsip" ]]; then
	        break
            else	
                echo "WARNING : the IP of your server is not the same than reported by the dns for domain $fqdn"
                echo "Are you really SURE that you want to setup Loreji with these parameters?"
                read -e -p "(y):accept, (n):change fqdn or ip retry, (ctrl+c):quit installer? " yn
                case $yn in
                   [Yy]* ) break;;
                esac
	          fi
        fi
    fi
done
echo ""
while true; do
    read -e -p "Loreji is now ready to install, do you wish to continue (y/n)? " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) exit;
    esac
done

# ***************************************
# Installation really starts here

# Set custom logging methods so we create a log file in the current working directory.
logfile=$$.log
touch $$.log
exec > >(tee $logfile)
exec 2>&1
echo -e "Installing Loreji $Loreji_GitHubVersion with fqdn $fqdn and ip $publicip\n"
uname -a
echo ""

# AppArmor must be disabled to avoid problems
[ -f /etc/init.d/apparmor ]
if [ $? = "0" ]; then
    echo -e "\nDisabling and removing AppArmor, please wait..."
    /etc/init.d/apparmor stop &> /dev/null
    update-rc.d -f apparmor remove &> /dev/null
    apt-get remove -y --purge apparmor* &> /dev/null
    mv /etc/init.d/apparmor /etc/init.d/apparmpr.removed &> /dev/null
    echo "AppArmor has been removed."
fi

# Random password generator function
passwordgen() {
    l=$1
    [ "$l" == "" ] && l=16
    tr -dc A-Za-z0-9 < /dev/urandom | head -c ${l} | xargs
}

# Update the enabled Aptitude repositories
# echo -ne "\nUpdating Aptitude Repos: " >/dev/tty
# # - List all packages installed 
# dpkg --get-selections

# mkdir -p "/etc/apt/sources.list.d.save"
# cp -R "/etc/apt/sources.list.d/*" "/etc/apt/sources.list.d.save" &> /dev/null
# rm -rf "/etc/apt/sources.list/*"
# cp "/etc/apt/sources.list" "/etc/apt/sources.list.save"

# if [ "$VER" = "12.04" ]; then
# cat > /etc/apt/sources.list <<EOF
# #Depots main restricted
# deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc) main restricted
# deb http://security.ubuntu.com/ubuntu $(lsb_release -sc)-security main restricted
# deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-updates main restricted
 
# deb-src http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc) main restricted
# deb-src http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-updates main restricted
# deb-src http://security.ubuntu.com/ubuntu $(lsb_release -sc)-security main restricted

# #Depots Universe Multiverse 
# deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc) universe multiverse
# deb http://security.ubuntu.com/ubuntu $(lsb_release -sc)-security universe multiverse
# deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-updates universe multiverse

# deb-src http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc) universe multiverse
# deb-src http://security.ubuntu.com/ubuntu $(lsb_release -sc)-security universe multiverse
# deb-src http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-updates universe multiverse
# EOF
# elif [ "$VER" = "14.04" ]; then
# cat > /etc/apt/sources.list <<EOF
# #Depots main restricted
# deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) main restricted universe multiverse
# deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-security main restricted universe multiverse
# deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-updates main restricted universe multiverse
# EOF
# fi

# Ensure all packages are uptodate
echo -e "\nUpdating+upgrading system, it may take some time..."
apt-get update -yqq
apt-get upgrade -yqq

# Install some standard utility packages required by the installer and/or Loreji.
echo -e "\nDownloading and installing required tools..."
apt-get -y install sudo wget vim make zip unzip git debconf-utils at build-essential bash-completion

# Clone Loreji from GitHub
echo -e "\nDownloading Loreji, Please wait, this may take several minutes, the installer will continue after this is complete!"
git clone https://github.com/Loreji/LorejiPanel.git
cd Loreji/
git checkout Develop
mkdir ../loreji_install_cache/
git checkout-index -a -f --prefix=../loreji_install_cache/
cd ../loreji_install_cache/

# Set-up Loreji directories and configure permissions

# /etc
mkdir -p /etc/loreji/configs
mkdir -p /etc/loreji/ssl
mkdir -p /etc/loreji/static
mkdir -p /etc/loreji/temp

# /var
mkdir -p /var/loreji/temp
mkdir -p /var/loreji/hostdata/admin/public_html
mkdir -p /var/loreji/logs/proftpd
mkdir -p /var/loreji/backups

# Copy cloned git loreji to /etc/loreji
cp -R . /etc/loreji/

# Chmod/chown
chmod -R 777 /etc/loreji/
chmod -R 777 /var/loreji/
chmod -R 770 /var/loreji/hostdata/
chown -R www-data:www-data /var/loreji/hostdata/

# Setting executables
ln -s /etc/loreji/panel/bin/daemon /usr/bin/daemon
ln -s /etc/loreji/panel/bin/loreji /usr/bin/loreji
chmod +x /etc/loreji/panel/bin/daemon
chmod +x /etc/loreji/panel/bin/loreji
#cp -R /etc/loreji/panel/etc/build/config_packs/ubuntu_12_04/. /etc/loreji/configs/

# Ensure tmp is owned by root and fully accessible 
chown root:root /tmp
chmod 1777 /tmp

#---------------------------
# Install required softwares and dependencies required by Loreji.
# We disable the DPKG prompts before we run the software install to enable fully automated install.
export DEBIAN_FRONTEND=noninteractive

#--- MySQL
echo -e "\n# Installing MySQL"
mysqlpassword=$(passwordgen);
apt-get -yqq install bsdutils
apt-get -yqq install mysql-server libsasl2-modules-sql libsasl2-modules
if [ "$VER" = "12.04" ]; then
  apt-get install -qqy db4.7-util
fi

service mysql start
mysqladmin -u root password "$mysqlpassword"
until mysql -u root -p"$mysqlpassword" -e ";" > /dev/null 2>&1 ; do
    read -s -p "enter your root mysql password : " mysqlpassword
done

sed -i "s|YOUR_MYSQL_ROOT_PASSWORD|$mysqlpassword|" /etc/loreji/panel/init.sample.php
mv /etc/loreji/panel/init.sample.php /etc/loreji/panel/init.php

mysql -u root -p"$mysqlpassword" -e "DROP DATABASE IF EXISTS test";
mysql -u root -p"$mysqlpassword" -e "DELETE FROM mysql.user WHERE User=''";
mysql -u root -p"$mysqlpassword" -e "FLUSH PRIVILEGES";
mysql -u root -p"$mysqlpassword" -e "CREATE SCHEMA loreji_roundcube";
mysql -u root -p"$mysqlpassword" -e "CREATE SCHEMA loreji_ccunit";
mysql -u root -p"$mysqlpassword" -e "CREATE SCHEMA loreji_core";
cat /etc/loreji/configs/loreji-install/sql/*.sql | mysql -u root -p"$mysqlpassword"

mysql -u root -p"$mysqlpassword" -e "use loreji_core; UPDATE settings SET se_value_vc='$fqdn' WHERE se_key_vc='panel_domain';";


mysql -u root -p"$mysqlpassword" -e "FLUSH PRIVILEGES";
sed -i "/ssl-key=/a \secure-file-priv = /var/tmp" /etc/mysql/my.cnf

#--- Postfix
echo -e "\n# Installing Postfix"
postfixpassword=$(passwordgen);
mysql -u root -p"$mysqlpassword" -e "UPDATE mysql.user SET Password=PASSWORD('$postfixpassword') WHERE User='postfix' AND Host='localhost';";
apt-get -qqy install postfix postfix-mysql 
mkdir /var/loreji/vmail
chmod -R 770 /var/loreji/vmail
useradd -r -u 150 -g mail -d /var/loreji/vmail -s /sbin/nologin -c "Virtual maildir" vmail
chown -R vmail:mail /var/loreji/vmail
mkdir -p /var/spool/vacation
useradd -r -d /var/spool/vacation -s /sbin/nologin -c "Virtual vacation" vacation
chmod -R 770 /var/spool/vacation
ln -s /etc/loreji/configs/postfix/vacation.pl /var/spool/vacation/vacation.pl
postmap /etc/postfix/transport
chown -R vacation:vacation /var/spool/vacation
if ! grep -q "127.0.0.1 autoreply.$fqdn" /etc/hosts; then echo "127.0.0.1 autoreply.$fqdn" >> /etc/hosts; fi
sed -i "s|myhostname = control.yourdomain.com|myhostname = $fqdn|" /etc/loreji/configs/postfix/main.cf
sed -i "s|mydomain = control.yourdomain.com|mydomain   = $fqdn|" /etc/loreji/configs/postfix/main.cf
rm -rf /etc/postfix/main.cf /etc/postfix/master.cf
ln -s /etc/loreji/configs/postfix/master.cf /etc/postfix/master.cf
ln -s /etc/loreji/configs/postfix/main.cf /etc/postfix/main.cf
sed -i "s|password \= postfix|password \= $postfixpassword|" /etc/loreji/configs/postfix/mysql-relay_domains_maps.cf
sed -i "s|password \= postfix|password \= $postfixpassword|" /etc/loreji/configs/postfix/mysql-virtual_alias_maps.cf
sed -i "s|password \= postfix|password \= $postfixpassword|" /etc/loreji/configs/postfix/mysql-virtual_domains_maps.cf
sed -i "s|password \= postfix|password \= $postfixpassword|" /etc/loreji/configs/postfix/mysql-virtual_mailbox_limit_maps.cf
sed -i "s|password \= postfix|password \= $postfixpassword|" /etc/loreji/configs/postfix/mysql-virtual_mailbox_maps.cf
sed -i "s|\$db_password \= 'postfix';|\$db_password \= '$postfixpassword';|" /etc/loreji/configs/postfix/vacation.conf
# small touch to remove unusued directives
sed -i '/virtual_mailbox_limit_maps/d' /etc/postfix/main.cf
sed -i '/smtpd_bind_address/d' /etc/postfix/master.cf

#--- Dovecot (includes Sieve)
echo -e "\n# Installing Dovecot"
apt-get install -qqy dovecot-mysql dovecot-imapd dovecot-pop3d dovecot-common dovecot-managesieved dovecot-lmtpd 
mkdir -p /var/loreji/sieve
chown -R vmail:mail /var/loreji/sieve
mkdir -p /var/lib/dovecot/sieve/
touch /var/lib/dovecot/sieve/default.sieve
ln -s /etc/loreji/configs/dovecot2/globalfilter.sieve /var/loreji/sieve/globalfilter.sieve
rm -rf /etc/dovecot/dovecot.conf
ln -s /etc/loreji/configs/dovecot2/dovecot.conf /etc/dovecot/dovecot.conf
sed -i "s|postmaster_address = postmaster@your-domain.tld|postmaster_address = postmaster@$fqdn|" /etc/dovecot/dovecot.conf
sed -i "s|password=postfix|password=$postfixpassword|" /etc/loreji/configs/dovecot2/dovecot-dict-quota.conf
sed -i "s|password=postfix|password=$postfixpassword|" /etc/loreji/configs/dovecot2/dovecot-mysql.conf
touch /var/log/dovecot.log
touch /var/log/dovecot-info.log
touch /var/log/dovecot-debug.log
chown vmail:mail /var/log/dovecot*
chmod 660 /var/log/dovecot*

#--- ProFTPD
echo -e "\n# Installing ProFTPD"
apt-get install -qqy proftpd-mod-mysql
groupadd -g 2001 ftpgroup
useradd -u 2001 -s /bin/false -d /bin/null -c "proftpd user" -g ftpgroup ftpuser
sed -i "s|#SQLConnectInfo  loreji_proftpd@localhost root password_here|SQLConnectInfo   loreji_proftpd@localhost root $mysqlpassword|" /etc/loreji/configs/proftpd/proftpd-mysql.conf
rm -rf /etc/proftpd/proftpd.conf
touch /etc/proftpd/proftpd.conf
if ! grep -q "include /etc/loreji/configs/proftpd/proftpd-mysql.conf" /etc/proftpd/proftpd.conf; then
    echo "include /etc/loreji/configs/proftpd/proftpd-mysql.conf" >> /etc/proftpd/proftpd.conf; 
fi
chmod -R 644 /var/loreji/logs/proftpd
serverhost=$(hostname)

#--- Apache HTTPD
echo -e "\n# Installing Apache"
apt-get install -qqy apache2 libapache2-mod-bw
if ! grep -q "Include /etc/loreji/configs/apache2.conf" /etc/apache2/apache2.conf; then
    echo "Include /etc/loreji/configs/apache2.conf" >> /etc/apache2/apache2.conf; 
fi

sed -i 's|DocumentRoot /var/www/html|DocumentRoot /etc/loreji/panel|' /etc/apache2/sites-enabled/000-default.conf
sed -i 's|<Directory /var/www/>|<Directory /etc/loreji/panel>|' /etc/apache2/apache2.conf

chown -R www-data:www-data /var/loreji/temp/

if ! grep -q "127.0.0.1 $fqdn" /etc/hosts; then
    echo "127.0.0.1 $fqdn" >> /etc/hosts; 
fi

a2enmod rewrite
a2enmod ssl

#--- PHP
echo -e "\n# Installing PHP"
apt-get install -qqy libapache2-mod-php5 php5-common php5-cli php5-mysql php5-gd php5-mcrypt php5-curl php-pear php5-imap php5-xmlrpc php5-xsl
if [ "$VER" = "12.04" ]; then
    apt-get install -qqy php5-suhosin
fi
sed -i "s|;date.timezone =|date.timezone = $tz|" /etc/php5/cli/php.ini
sed -i "s|;date.timezone =|date.timezone = $tz|" /etc/php5/apache2/php.ini
sed -i "s|;upload_tmp_dir =|upload_tmp_dir = /var/loreji/temp/|" /etc/php5/cli/php.ini
sed -i "s|;upload_tmp_dir =|upload_tmp_dir = /var/loreji/temp/|" /etc/php5/apache2/php.ini
sed -i "s|expose_php = On|expose_php = Off|" /etc/php5/apache2/php.ini
#ensure session save dir is reachable and protected
chmod 733 /var/lib/php5
chmod +t /var/lib/php5

# Ubutu 14.04 need to build suhosin
echo -e "\n# Building suhosin"
apt-get install -qqy php5-dev
git clone https://github.com/stefanesser/suhosin
cd suhosin
phpize
./configure
make
make install
cd ..
rm -rf suhosin
sed -i 'N;/default extension directory./a\extension=suhosin.so' /etc/php5/cli/php.ini
sed -i 'N;/default extension directory./a\extension=suhosin.so' /etc/php5/php.ini


# Permissions fix for Apache and ProFTPD (to enable them to play nicely together!)
if ! grep -q "umask 002" /etc/apache2/envvars; then echo "umask 002" >> /etc/apache2/envvars; fi
if ! grep -q "127.0.0.1 $serverhost" /etc/hosts; then echo "127.0.0.1 $serverhost" >> /etc/hosts; fi
usermod -a -G www-data ftpuser
usermod -a -G ftpgroup www-data
service apache2 restart

#--- CRON specific installation tasks...
echo -e "\n# Installing Cron tasks"
mkdir -p /var/spool/cron/crontabs/
mkdir -p /etc/cron.d/
touch /var/spool/cron/crontabs/www-data
touch /etc/cron.d/www-data
date +"%H:%M:%S"
crontab -u www-data /var/spool/cron/crontabs/www-data
date +"%H:%M:%S"
#cp /etc/loreji/configs/cron/zdaemon /etc/cron.d/zdaemon
chmod -R 644 /var/spool/cron/crontabs/
chmod 744 /var/spool/cron/crontabs
chmod -R 644 /etc/cron.d/
chown -R www-data:www-data /var/spool/cron/crontabs/
date +"%H:%M:%S"

#--- Webalizer specific installation tasks...
echo -e "\n# Installing Webalizer"
apt-get install -qqy webalizer 
rm -rf /etc/webalizer/webalizer.conf

#--- Roundcube specific installation tasks...
echo -e "\n# Configuring Roundcube"
roundcube_des_key=$(passwordgen 24);
sed -i "s|YOUR_MYSQL_ROOT_PASSWORD|$mysqlpassword|" /etc/loreji/panel/panel/apps/roundcube/config/config.inc.php
#sed -i "s|#||" /etc/loreji/configs/roundcube/db.inc.php
#sed -i "s|rcmail-!24ByteDESkey\*Str|$roundcube_des_key|" /etc/loreji/panel/panel/apps/roundcube/config/main.inc.php

# Set some Loreji database entries using. setso and setzadmin
echo -e "\n# Configuring Loreji"
loreji management adminpass

# Enable system services and start/restart them as required.
echo -e "\n# Starting/restarting services"
daemon
service apache2 restart
service postfix restart
service dovecot start
service cron reload
service proftpd start
service atd start

# Remove temporary install directories.
cd ../
rm -rf loreji_install_cache/

# Store the passwords for user reference
{
    echo "admin Password       : your chosen password"
    echo "MySQL Root Password   : $mysqlpassword"
    echo "MySQL Postfix Password: $postfixpassword"
    echo "IP Address: $publicip"
    echo "Panel Domain: $fqdn"
} >> /root/passwords.txt

# Advise the user that Loreji is now installed and accessible.
echo "#########################################################" &>/dev/tty
echo " Congratulations Loreji has now been installed on your"   &>/dev/tty
echo " server. Please review the log file left in /root/ for "   &>/dev/tty
echo " any errors encountered during installation."              &>/dev/tty
echo ""                                                          &>/dev/tty
echo " Save the following information somewhere safe:"           &>/dev/tty
echo " MySQL Root Password    : $mysqlpassword"                  &>/dev/tty
echo " MySQL Postfix Password : $postfixpassword"                &>/dev/tty
echo " Loreji Username       : zadmin"                          &>/dev/tty
echo " Loreji Password       : $zadminpassword"                 &>/dev/tty
echo ""                                                          &>/dev/tty
echo " Loreji Web login can be accessed using your server IP"   &>/dev/tty
echo " inside your web browser."                                 &>/dev/tty
echo "#########################################################" &>/dev/tty
echo "" &>/dev/tty

# We now request that the user restarts their server...
read -e -p "You must restart your server now to complete the install (y/n)? " rsn
while true; do
    case $rsn in
        [Yy]* ) break;;
        [Nn]* ) exit;
    esac
done
shutdown -r now