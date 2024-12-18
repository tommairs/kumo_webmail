# KumoMTA with webmail 
A guide to installing [KumoMTA](https://kumomta.com/) + [Dovecot](https://doc.dovecot.org/2.3/) + [Roundcube](https://roundcube.net/) for Webmail inboxes

[KumoMTA](https://docs.kumomta.com/) is a powerful Message Transport Agent, but it does not come bundled with any graphic UI of any kind, and that includes mailbox handling.
In a recent release, we included the ability to write messages to local maildir format mailboxes in order to allow for inbound message processing.  
This type of handling can include anti-virus scanning, store and forward functions, legal intercept storage, postmaster mailboxes, and many other uses.  

This tutorial explains how to access those inboxes with webmail.  There are a few options to choose from, but for the sake of this tutorial we will install Roundcube as a webmail front end. Roundcube requires an IMAP mail server which KumoMTA is not, so you need Dovecot to provide the IMAP services.  Roudcube also needs Apache HTTPD, PHP and and Database (we will use MySQL) in order to function properly.

Buckle up - here we go.

## Prep the system and get the required (and helpful) packages:
```bash
sudo apt-get autoclean
sudo apt-get -y update
sudo apt-get -y upgrade
sudo apt-get install -y firewalld tree telnet git bind9 bind9-utils vim jq zip unzip wget composer curl
```

Get the Apache, PHP, MySQL, Dovecot packages you will need later
```bash
sudo apt-get install -y apache2 php libapache2-mod-php php-xml php-mbstring php-intl php-zip php-pear php-curl php8.1-imagick php-mysql mysql-common mysql-server php-mysql 
sudo apt-get install -y dovecot-core dovecot-pop3d dovecot-imapd dovecot-lmtpd
```

Get Roundcube:
```bash
wget https://github.com/roundcube/roundcubemail/releases/download/1.6.9/roundcubemail-1.6.9-complete.tar.gz
tar -xvzf roundcubemail-1.6.9-complete.tar.gz 

sudo mkdir -p /var/www/
sudo mv roundcubemail-1.6.9 /var/www/roundcube
sudo chown -R www-data:www-data /var/www/roundcube/
sudo chmod 775 /var/www/roundcube/temp/ /var/www/roundcube/logs/
```

Ensure your firewall has all the ports open it needs for imap (and pop3 if you are using it).  With `firewalld` it looks a bit like this:

```bash
sudo firewall-cmd --zone=public --permanent --add-service=imap
sudo firewall-cmd --zone=public --permanent --add-service=imaps
sudo firewall-cmd --zone=public --permanent --add-service=pop3
sudo firewall-cmd --zone=public --permanent --add-service=pop3s
```

## Install and configure KumoMTA

There is a good tutorial on the KumoMTA documentation site that will get you a working install:
[https://docs.kumomta.com/tutorial/quickstart/](https://docs.kumomta.com/tutorial/quickstart/)

There is also a 3rd-party installer here that will install a very basic version of the latest KumoMTA:
[https://github.com/tommairs/KumoMTAInstaller](https://github.com/tommairs/KumoMTAInstaller)
You can git clone the code there and run it as described.

Once KumoMTA is functional, ensure you add the MAILDIR functionality described here:
[https://docs.kumomta.com/reference/kumo/make_queue_config/protocol/](https://docs.kumomta.com/reference/kumo/make_queue_config/protocol/?h=maildir#advanced-maildir-path]

There is also a working config here that includes that if you want to copy or compare:
[https://github.com/tommairs/kumo_config](https://github.com/tommairs/kumo_config)

* NOTE: If you copy that whole config to /opt/kumomta/etc/policy/ then you will now have a working email server that will store select domain emails to a local MAILDIR compatible with webmail.

Otherwise, review the instructions here: 
https://docs.kumomta.com/reference/kumo/make_queue_config/protocol/?h=maildir#advanced-maildir-path

Make sure you create the actual maildir directory and set permissions. That does not happen automatically. 
```bash
sudo mkdir /var/maildirs/
sudo chown kumod /var/maildirs/
```

Test and make sure KumoMTA work and you can send and receive mail and that the maildir fills out as expected:
```ls -asltr /var/maildirs/kumomta.com/tom/new/
total 24
4 -rw-rw-r-- 1 kumod kumod  810 Dec 17 23:12 '1734477131.#0M525277478P4580V66306I517241.webmail.kumomta.com,S=810'
```

Once confirmed, you can move on to Dovecot and Roundcube configs.

## Start with Apache2 HTTPD server
If you installed Apache2 HTTPD in the prep step above, then you just need to configure it. It is easiest to copy the sample site and modify it.
```bash
sudo cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/roundcube.conf
sudo vi /etc/apache2/sites-available/roundcube.conf
```

### Edit roundcube.conf so it looks something like this:
Obviously, you should change `ServerName` and `ServerAdmin` to your own values.

```bash
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
```

Now also modify the php config to uncomment the `mbstring` extension:

`sudo vi /etc/php/8.1/apache2/php.ini`

Modify mbstring extension:
;extension=imap
;extension=ldap
extension=mbstring   ;**<== Uncomment this**
;extension=exif      ; Must be after mbstring as it depends on it


And set the timezone (change it to yours not mine):
`date.timezone = "America/Edmonton"`


Now disable the default site, enable the roundcube config, and restart apache.

```bash
sudo a2dissite 000-default
sudo a2ensite roundcube
sudo a2enmod rewrite	
sudo a2enmod php8.1 
sudo systemctl restart apache2
```

## Configure MySQL

Wait, what?  Why do I need a Database?
Well, this is where life gets a little complicated. 
1) Roundcube needs its own DB for storing messages, states, users, etc. It does not have its own message store or MTA, but is a nice interface that will connect to a message service.
2) Dovecot needs its own DB for storing user credentials, mail dir locations, and other data.
These can be separate DBs in separate places, but in our case, we are running it all on one server, so we might as well use one DB with separate tables.  The database itself could be MySQL, PGSQL, SQLite, or a number of other data sources. It may be worth reading the associated documentation if you are interested.  For the purpose of this particular tutorial, we are going to use MySQL.
   
* NOTE: On Ubuntu, you may have to reset the root password before using ...
```bash
sudo mysql
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'password';
exit
```
... and I usually run the `secure install` script when installing a new MySQL.
`mysql_secure_installation`
 ... follow the prompts

Now that you have a working MySQL, set up the tables you will need:
login with the root password you created in the step above:
`mysql -u root -p`

Create the databases for roundcube and dovecot.  You can change the names and password here, but be consistent in the rest of the tutorial.  
I only created one admin user with permissions over both databases - you can change that if necessary, but be consistent in the rest of this tutorial.
```bash
CREATE DATABASE roundcubemail /*!40101 CHARACTER SET utf8 COLLATE utf8_general_ci */;
CREATE DATABASE usermail /*!40101 CHARACTER SET utf8 COLLATE utf8_general_ci */;
CREATE USER 'dbadmin'@'localhost' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON roundcubemail.* to 'dbadmin'@'localhost';
GRANT ALL PRIVILEGES ON usermail.* to 'dbadmin'@'localhost';
FLUSH PRIVILEGES;
```
Create the Dovecot users table in the usermail database:
```bash
use usermail
CREATE TABLE users (
  userid VARCHAR(128) NOT NULL,
  domain VARCHAR(128) NOT NULL,
  password VARCHAR(64) NOT NULL,
  home VARCHAR(255) NOT NULL,
  uid INTEGER NOT NULL,
  gid INTEGER NOT NULL
);
```

You may also want to add credentials here now, or you can add them later, but THESE are the credentials that ROUNDCUBE will use to login.  Yes, `ROUNDCUBE` will use the `DOVECOT` credentials to login to the mailbox.  Also note that Roundcube will use MD5 encrypted passwords by default, so do this first:

```bash
sudo doveadm pw -s MD5-CRYPT
```
Enter the password for your user (twice to verify) then copy and paste the result into the password field in the INSERT below.
Remember that step as you will need to repeat (or automate) that for every user.

For the home, uid and gid values, you need to use the kumod user `cat /etc/passwd |grep kumod` and use the maildir home for the home value.

```bash
INSERT INTO TABLE users (userid,domain,password,home,uid,gid) VALUES('bob','example.com','{MD5-CRYPT}$1$0utcK8zl$vYpspZ0WhddKiX/IW.JfJ1','/var/maildirs/',1001,1001);
```
and 

```bash
EXIT;
```
Roundcube has a handy sql template you can just import for that table:
```bash
mysql -u dbadmin -p roundcubemail < /var/www/roundcube/SQL/mysql.initial.sql
```

## Now configure Dovecot

You have configured credentials in MySQL, but Dovecot still needs to know you did that, so 
edit your dovecot-sql.conf.ext file:
```bash
sudo vi dovecot-sql.conf.ext
```
And modify or add these:
```bash
driver = mysql
connect = host=/var/run/mysqld/mysqld.sock dbname=usermail user=dbadmin password=password

password_query = SELECT userid AS username, domain, password \
FROM users WHERE userid = '%n' AND domain = '%d'
user_query = SELECT home, uid, gid FROM users WHERE userid = '%n' AND domain = '%d'

# For using doveadm -A:
iterate_query = SELECT userid AS username, domain FROM users
```

Now also create or modify `/etc/dovecot/local.conf` with data that looks like this:
```bash
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
login_trusted_networks = 54.244.210.27 172.31.29.198
```

After all these changes, you need to reload dovecot with `sudo doveadm reload`

You can check the log for errors with `cat /var/log/dovecot.log`


Now open a web browser to your server location to finish the installation and testing of roundcube:
`http://mywebmailserver.com/installer/`
And follow the steps there to finish configuring and testing

Once you have a "green light" on the testing, you can delete the install folder for security reasons, then point your browser to your new webmail site and login.
`http://mywebmailserver.com`

## Further reading and support

There is a decent tutorial here on Roundcude on Ubuntu:
[installing-webmail-client-with-roundcube-on-ubuntu-20-04-a-tutorial](https://blog.cloudsigma.com/installing-webmail-client-with-roundcube-on-ubuntu-20-04-a-tutorial/)

And a decent tutorial here on Dovecot on Ubuntu:
[how-to/mail-services/install-dovecot](https://documentation.ubuntu.com/server/how-to/mail-services/install-dovecot/)

Important KumoMTA documentation is here:
[Install tutorial](https://docs.kumomta.com/tutorial/quickstart/) 
[Maildir support](https://docs.kumomta.com/reference/kumo/make_queue_config/protocol/?h=maildir#advanced-maildir-path) 

