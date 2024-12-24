###################################################
# An attempt at a bash installer for the
# KumoMTA + Dovecot + Roundcube project
###################################################

###################################################
#
#  THIS SCRIPT IS UNTESTED AND EXPERIMENTAL
#   -- HERE BE DRAGONS --
#
###################################################
#
# The prep work
sudo apt-get autoclean
sudo apt-get -y update
sudo apt-get -y upgrade
sudo apt-get install -y firewalld tree telnet git bind9 bind9-utils vim jq zip unzip wget composer curl

# Get Dovecot, Apache, PHP, MySQL
sudo apt-get install -y apache2 php libapache2-mod-php php-xml php-mbstring php-intl php-zip php-pear php-curl php8.1-imagick php-mysql mysql-common mysql-server php-mysql 
sudo apt-get install -y dovecot-core dovecot-pop3d dovecot-imapd dovecot-lmtpd

# Get roundcube
wget https://github.com/roundcube/roundcubemail/releases/download/1.6.9/roundcubemail-1.6.9-complete.tar.gz
tar -xvzf roundcubemail-1.6.9-complete.tar.gz 

sudo mkdir -p /var/www/
sudo mv roundcubemail-1.6.9 /var/www/roundcube
sudo chown -R www-data:www-data /var/www/roundcube/
sudo chmod 775 /var/www/roundcube/temp/ /var/www/roundcube/logs/

# Update firewall
sudo firewall-cmd --zone=public --permanent --add-service=imap
sudo firewall-cmd --zone=public --permanent --add-service=imaps
sudo firewall-cmd --zone=public --permanent --add-service=pop3
sudo firewall-cmd --zone=public --permanent --add-service=pop3s

# Install KumoMTA
git clone https://github.com/tommairs/KumoMTAInstaller
git clone https://github.com/tommairs/kumo_config

sudo mkdir /var/maildirs/
sudo chown kumod /var/maildirs/

# Configure Apache
sudo cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/roundcube.conf
sudo vi /etc/apache2/sites-available/roundcube.conf

cat "
<VirtualHost *:80>
  ServerName webmail.myawesomedomain.com
  DocumentRoot /var/www/roundcube
  ServerAdmin webmailadmin@myawesomedomain.com
  ErrorLog ${APACHE_LOG_DIR}/roundcube-error.log
  CustomLog ${APACHE_LOG_DIR}/roundcube-access.log combined
  <Directory /var/www/roundcube>
    Options -Indexes
    AllowOverride All
    Order allow,deny
    allow from all
  </Directory>
</VirtualHost>
" > /var/www/roundcube/config/roundcube.conf

sed -i /;extension=mbstring/extension=mbstring/ /etc/php/8.1/apache2/php.ini


sudo a2dissite 000-default
sudo a2ensite roundcube
sudo a2enmod rewrite	
sudo a2enmod php8.1 
sudo systemctl restart apache2


## Can this actually be done with bash??
sudo mysql
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'password';
exit

CREATE DATABASE roundcubemail /*!40101 CHARACTER SET utf8 COLLATE utf8_general_ci */;
CREATE DATABASE usermail /*!40101 CHARACTER SET utf8 COLLATE utf8_general_ci */;
CREATE USER 'dbadmin'@'localhost' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON roundcubemail.* to 'dbadmin'@'localhost';
GRANT ALL PRIVILEGES ON usermail.* to 'dbadmin'@'localhost';
FLUSH PRIVILEGES;

use usermail
CREATE TABLE users (
  userid VARCHAR(128) NOT NULL,
  domain VARCHAR(128) NOT NULL,
  password VARCHAR(64) NOT NULL,
  home VARCHAR(255) NOT NULL,
  uid INTEGER NOT NULL,
  gid INTEGER NOT NULL
);


set OUTPASS = `sudo doveadm pw -s MD5-CRYPT`

INSERT INTO TABLE users (userid,domain,password,home,uid,gid) VALUES('bob','example.com','$OUTPASS','/var/maildirs/',1001,1001);
EXIT;

mysql -u dbadmin -p roundcubemail < /var/www/roundcube/SQL/mysql.initial.sql

cat "
driver = mysql
connect = host=/var/run/mysqld/mysqld.sock dbname=usermail user=dbadmin password=password

password_query = SELECT userid AS username, domain, password \
FROM users WHERE userid = '%n' AND domain = '%d'
user_query = SELECT home, uid, gid FROM users WHERE userid = '%n' AND domain = '%d'

# For using doveadm -A:
iterate_query = SELECT userid AS username, domain FROM users
" >> dovecot-sql.conf.ext


cat "
protocols = imap pop3

# It's nice to have separate log files for Dovecot. 
log_path = /var/log/dovecot.log
info_log_path = /var/log/dovecot-info.log

# Disable SSL for now, but it can be enabled later for production.
ssl = no
disable_plaintext_auth = no

# We're using Maildir format, so let Dovecot know where that maildir is.
# %d = domain, %n = localpart of email address
# mail for tom@kumomta.com will end up in /var/maildirs/kumomta.com/tom/
mail_location = maildir:/var/maildirs/%d/%n

# If you're using POP3, you'll need this:
pop3_uidl_format = %g

# Authentication configuration:
auth_verbose = yes
auth_mechanisms = plain login
passdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
userdb {
  driver = static
  args = uid=kumod gid=kumod home=/var/maildirs/%d/%n
}

# If you are using Roundcube on a system that is NOT this localhost,
#   then you should include its IP(s) here or you not be able to login.
login_trusted_networks = 54.244.210.27 172.31.29.198"
 > /etc/dovecot/local.conf






