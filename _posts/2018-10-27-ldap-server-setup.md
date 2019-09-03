---
layout: post
title: "Directory Services 101: Setting up an LDAP server"
categories: tech
---

This post is part of a series on directory services. Current available
installments are:

* [Introduction](/2017/07/02/ldap-101.html)
* [Terminology](/2017/07/02/ldap-terminology.html)
* [Basic concepts](/2017/08/26/ldap-basics.html)
* [Designing the DIT](/2018/10/26/ldap-designing-dit)
* [Setting up an LDAP server](/2018/10/27/ldap-server-setup)
* [Securing your LDAP server](/2018/10/27/ldap-secure)
* [Writing and testing ACLs](/2018/10/27/ldap-writing-testing-acls)

---

I consider setting up a Directory Service a pretty big pain in the ass,
especially OpenLDAP. Microsoft fares much better with Active Directory
which is also much more easily configured for folks less familiar with
directory services in general.

I'd be remiss not to point out that you don't have to host your own
LDAP server nowadays anymore. Microsoft Azure Active Directory is a
viable option and so is Google's recently announced LDAP service. However
not everyone is comfortable handing out the source of identity to a third
party (and I would urge you to carefully think through that). There are
also some limitations that apply to hosted services like limited or no
support for custom schemas (user defined object classes and attributes).

To that end this guide will cover setting up OpenLDAP. This can help you
bootstrap an OpenLDAP environment or let you spin up a local one in order
to develop a service against it.

One important thing to note, this guide will setup OpenLDAP with online/dynamic
configuration, also known as "olc" (because all the attribute names related
to it are prefixed with `olc`). This means that the configuration of the
OpenLDAP server is stored inside the directory service itself, as object
classes with attributes and that you'll need to modify those. The reason
it's called online configuration is because changing those configuration
options takes immediate effect, versus having to restart the service if
you used the older approach of having a `slapd.conf` file instead. It also
means that if you run OpenLDAP with `syncrepl` replication, the configuration
change will automatically propagate to all replicas.

## Table of Contents

* [Table of Contents](#table-of-contents)
* [Tools](#tools)
* [Bootstrapping](#bootstrapping)
* [Connecting to the directory service](#connecting-to-the-directory-service)
* [Seeding data](#seeding-data)
* [Next up](#next-up)

## Tools

I find it rather helpful to have a visual, point-and-click, kind of way to
browse the DIT and interact with the directory service. I've found no better
tool to do so than [Apache Directory Studio][ads]. Especially if you're not all
that familiar with LDAP this should help you out a lot.

I run my LDAP servers as Docker containers, though this is of course not
required. It's rather helpful when experiment though, so I would recommend to
at least have Docker installed on your laptop.

Last but not least, you'll need Python and [slapddgen][sdg]. `slapddgen` will
generate a `slapd.d` configuration for you that you can start an OpenLDAP server
from, complete with RFC 2307bis schema and some useful ACLs to get you started.

I'd recommend you to take a look at `slapddgen`'s templates and its README.
They're fairly simple to grasp and all attributes are easily researched online.
You're also welcome to change the templates to suit your needs, but be careful
when doing so as it can result in a broken configuration.

[ads]: https://directory.apache.org/studio/downloads.html
[sdg]: https://github.com/daenney/slapddgen

## Bootstrapping

Once you've installed `slapddgen`, `pip install slapddgen`, you can run it like
so:

```sh
$ slapddgen generate --output_dir=./

Setting up environment
Created temporary workspace
Rendered templates
Written CRC to all files
All done, result can be found in ./
```

You can change a number of configuration options by tweaking the values in
`config.json` and pointing to it with `--config_file=<path>`. The configuration
slapddgen generates targets Alpine, since that is what I base my Docker containers
on. You can use Ubuntu or CentOS for example but in that case you'll have to adjust
the `argsFile`, `configFile`, `configDir`, `pidFile` and `modulePath` options to
match what those packages expect.

Slapddgen's README has pretty extensive instructions on how to build and run this
in a container. If you want to run it on a physical host you'll have to copy the
generated `slapd.d` to the right path, usually something like `/etc/openldap/slapd.d`
or `/etc/ldap/slapd.d`.

## Connecting to the directory service

This is where Apache Directory Studio comes in. Start it and go to File > New >
LDAP Browser > LDAP Connection. Fill in either the hostname or the IP of the
server in the "Hostname" field and change the port if necessary. Leave the
"Encryption method" on "No encryption" (we'll fix this later, promise) and click
"Next".

Stick to "Simple Authentication", with a "Bind DN" of `cn=Manager,dc=example,dc=com`
and a password of `seed` (both these things are configurable through `config.json`).

On the "Browser Options" ensure "Get base DNs from root DSE" is checked. Click
finish and connect to the server!

You can now browse around. Since there's no entries at all there's really not
much to see right now.

You can also use command line tools to do much of this. The `ldapwhomami`
command can be used to authenticate and will return the DN of the authenticated
entity. For example: `ldapwhoami -H ldap://127.0.0.1:389 -x -W -D "cn=Manager,dc=example,dc=com"`.
This will then prompt you for your password and should then respond with
`dn:cn=Manager,dc=example,dc=com`.

To retrieve all entries in the DIT we can use `ldapsearch`:
`ldapsearch -H ldap://127.0.0.1:389 -x -W -D "cn=Manager,dc=example,dc=com" -b "dc=example,dc=com" -L *`.
After entering your password it'll return all entries in the DIT. This happens
because we set the base from with to search on to the root of the DIT with `-b`
and then provided a search filter of `*`.

## Seeding data

At this point you'll probably want to seed some data. This can be done by
writing and applying `ldif` files to the directory service. Ldifs describe
changes to be made and allow you to create, modify or delete entities.

The first thing you'll want to do is create the structure you intend to
use. If we proceed based on the DIT layout I described in the previous
post you'd end up with a file like this:

```ldif
dn: dc=example,dc=com
changetype: add
objectClass: dcObject
objectClass: organization
dc: example
o: Example dot Com

dn: cn=admin,dc=example,dc=com
changetype: add
objectClass: organizationalRole
cn: admin

dn: ou=example,dc=example,dc=com
changetype: add
objectClass: organizationalUnit
ou: example

dn: ou=accounts,ou=example,dc=example,dc=com
changetype: add
objectClass: organizationalUnit
ou: accounts

dn: ou=people,ou=accounts,ou=example,dc=example,dc=com
changetype: add
objectClass: organizationalUnit
ou: people

dn: ou=robots,ou=accounts,ou=example,dc=example,dc=com
changetype: add
objectClass: organizationalUnit
ou: robots

dn: ou=groups,ou=example,dc=example,dc=com
changetype: add
objectClass: organizationalUnit
ou: groups

dn: ou=userPrivate,ou=groups,ou=example,dc=example,dc=com
changetype: add
objectClass: organizationalUnit
ou: userPrivate
```

You can apply it using `ldapmodify`:

```sh
$ ldapmodify -a -x -D "cn=Manager,dc=example,dc=com" -W -H ldap://127.0.0.1:3389 -f 001-structure.ldif
Enter LDAP Password:
adding new entry "dc=example,dc=com"

adding new entry "cn=admin,dc=example,dc=com"

adding new entry "ou=example,dc=example,dc=com"

adding new entry "ou=accounts,ou=example,dc=example,dc=com"

adding new entry "ou=people,ou=accounts,ou=example,dc=example,dc=com"

adding new entry "ou=robots,ou=accounts,ou=example,dc=example,dc=com"

adding new entry "ou=groups,ou=example,dc=example,dc=com"

adding new entry "ou=userPrivate,ou=groups,ou=example,dc=example,dc=com"
```

You can build up similar seed files to provision new users, groups etc.
Here's another one, showing you how to provision a new user:

```ldif
dn: uid=test,ou=people,ou=accounts,ou=example,dc=example,dc=com
changetype: add
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: test
cn: test
sn: Tester
uidNumber: 10000
gidNumber: 10000
homeDirectory: /home/test
displayName: Testing test
mail: test@example.com
loginShell: /bin/bash
shadowExpire: 0
userPassword: {CRYPT}$6$rounds=50000$b7166V2Na/kA9Hs$Q05k3jHtVI41pNohCkFQbfWsDXEajYNDOmDj7lFX67Fvz14HmDOVaxaX8PAbysFUzkZsAv9ybQd4BSDc0JZPi.

dn: cn=test,ou=userPrivate,ou=groups,ou=example,dc=example,dc=com
changetype: add
objectClass: posixGroup
cn: test
gidNumber: 10000
memberUid: test
```

To make this account an admin, we'll need to add it as a `roleOccupant` on
`cn=admin`:

```ldif
dn: cn=admin,dc=example,dc=com
changetype: modify
add: roleOccupant
roleOccupant: uid=test,ou=people,ou=accounts,ou=example,dc=example,dc=com
```

## Next up

You should now have a working directory service with some basic configuration
and data in place. If you used slapddgen I'd recommend reading through its
README to understand all the configuration that was put in place for you.

If you followed the container setup it should be simple to spin up a new,
blank slate, directory service locally. I've found this to be very helpful
when experimenting with creating the DIT layout and to test ACL changes
before I ship those to the production instances. This can be especially
important as some ACL changes can (and will) lock you out of the system if
you get them wrong. There'll be a [separate article on ACLs](/2018/10/27/ldap-writing-testing-acls)
in this series.

Before we get to ACLs we'll take a look at [how to secure the directory
service](/2018/10/27/ldap-secure).
