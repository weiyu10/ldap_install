#!/bin/bash
# 安装和配置openldap+sasl+google_authenticator
# 操作系统: CentOS 7.2

# 管理员密码
root_password="ldapiswonderful"
dc_root="com"
dc_leaf="weiyu"
dc="dc=weiyu,dc=com"

# Gengrate root password
root_password_ssha=`slappasswd -s "${root_password}"`

# Build and install pam_google_authenticator module
if [ ! -e /usr/local/lib/security/pam_google_authenticator.so ]; then
    git clone https://github.com/google/google-authenticator.git
    cd google-authenticator/libpam
    ./bootstrap.sh
    ./configure
    make && sudo make install
fi
if [ ! -e /usr/local/lib/security/pam_google_authenticator.so ]; then
    echo "google_authenticator module build failed!"
    exit 1
fi

# Config and install cyrus-sasl
yum  -y install cyrus-sasl-plain cyrus-sasl-lib cyrus-sasl-devel cyrus-sasl oathtool

echo "
SOCKETDIR=/run/saslauthd
MECH=pam
FLAGS=
" > /etc/sysconfig/saslauthd

echo "
auth required /usr/local/lib/security/pam_google_authenticator.so forward_pass
auth required pam_unix.so use_first_pass
account include password-auth
" > /etc/pam.d/ldap

systemctl start saslauthd
systemctl enable saslauthd

# Check sasl config
adduser test -p test
su test -c "google-authenticator -t -d -f -r 1 -R 15 -w 3"
test_key=`cat /home/test/.google_authenticator  | head -1`
code=`oathtool --totp --base32 -d6 "${test_key}"` && testsaslauthd  -s ldap  -u test -p "test${code}"
if [ $? != 0 ]; then
    echo "testsaslauthd failed!"
    exit
fi

# Install packages and start service
yum install openldap-servers openldap-clients openldap git -y
if [ ! -f /var/lib/ldap/DB_CONFIG ]; then
    cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
fi
systemctl restart slapd
systemctl enable slapd

# Set root password
echo "
dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: ${root_password_ssha}
" > chrootpw.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f chrootpw.ldif

# import basic schema
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif

# Set root privilege
echo "
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth"
  read by dn.base="cn=root,${dc}" read by * none

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: ${dc}

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=root,${dc}

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: "${root_password_ssha}"

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by
  dn="cn=root,${dc}" write by anonymous auth by self write by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by dn="cn=root,${dc}" write by * read
" >  set_privilege.ldif
ldapmodify -Y EXTERNAL -H ldapi:/// -f set_privilege.ldif

# create dc and ou
echo "
dn: ${dc}
objectClass: top
objectClass: dcObject
objectclass: organization
o: base ou
dc: ${dc_leaf}

dn: cn=root,${dc}
objectClass: organizationalRole
cn: Manager
description: Directory Root

dn: ou=People,${dc}
objectClass: organizationalUnit
ou: People

dn: ou=Group,${dc}
objectClass: organizationalUnit
ou: Group
" > basedomain.ldif
ldapadd -x -D "cn=root,${dc}" -w "${root_password}" -f basedomain.ldif

# create user and group
echo "
dn: uid=test,ou=People,${dc}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: test
sn: test
givenName: test
displayName: test
uid: test
uidNumber: 10019
gidNumber: 5002
homeDirectory: /home/test
loginShell: /bin/bash
gecos: test
userPassword: {SASL}test@ci
description: User account
mail: test@gmail.com

dn: cn=devops,ou=Group,${dc}
objectClass: posixGroup
gidNumber: 5002
cn: devops
" > user_group.ldif
ldapadd -x -D "cn=root,${dc}" -w "${root_password}" -f user_group.ldif

# Config ldap use sasl
echo "
pwcheck_method: saslauthd
mech_list: plain login
" > /etc/sasl2/slapd.conf
systemctl restart slapd

# ldapsearch -x -LLL -b  ou=People,dc=weiyu,dc=com
# ldapwhoami -D "uid=test,ou=People,dc=weiyu,dc=com" -W -H ldap://
