#!/bin/bash
# A script for install and config ldap

# password=ldapiswonderful
ADMIN_PASSWORD="{SSHA}/xcP8pe3umm4UmGc185cU0yui3rYJ+AF"
DC_FIRST="weiyu"
DC="dc=weiyu,dc=com"

yum install openldap-servers openldap-clients openldap git -y
if [ ! -f /var/lib/ldap/DB_CONFIG ]; then
    cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
fi
systemctl restart slapd
systemctl enable slapd

# set root password
echo "
dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: ${ADMIN_PASSWORD}
" > chrootpw.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f chrootpw.ldif

# import schema
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif

# set privilege
echo "
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth"
  read by dn.base="cn=Manager,${DC}" read by * none

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: ${DC}

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=Manager,${DC}

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: "$ADMIN_PASSWORD"

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by
  dn="cn=Manager,${DC}" write by anonymous auth by self write by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by dn="cn=Manager,${DC}" write by * read
" >  chdomain.ldif
ldapmodify -Y EXTERNAL -H ldapi:/// -f chdomain.ldif

# create ou
echo "
dn: ${DC}
objectClass: top
objectClass: dcObject
objectclass: organization
o: base ou
dc: ${DC_FIRST}

dn: cn=Manager,${DC}
objectClass: organizationalRole
cn: Manager
description: Directory Manager

dn: ou=People,${DC}
objectClass: organizationalUnit
ou: People

dn: ou=Group,${DC}
objectClass: organizationalUnit
ou: Group
" > basedomain.ldif
ldapadd -x -D cn=Manager,dc=weiyu,dc=com -W -f basedomain.ldif

# create user and group
echo "
dn: uid=test,ou=People,${DC}
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
mail: weiyu@unitedstack.com

dn: cn=devops,ou=Group,${DC}
objectClass: posixGroup
gidNumber: 5002
cn: devops
" > group.ldif
ldapadd -x -D cn=Manager,dc=weiyu,dc=com -W -f group.ldif

echo "
pwcheck_method: saslauthd
mech_list: plain login
" > /etc/sasl2/slapd.conf
systemctl restart slapd

# ldapsearch -x -LLL -b  ou=People,dc=weiyu,dc=com
# ldapwhoami -D "uid=test,ou=People,dc=weiyu,dc=com" -W -H ldap://
