---
layout: post
title: "Directory Services 101: Securing your LDAP server"
date: "2018-10-27 10:00:00"
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

Now that we have a directory service up an running it's important we talk
a bit about some security aspects.

The configuration that was generated sets up the LDAP server in such a way
that anonymous access is not allowed. This means that for any operation
someone will need a valid account, and therefor have to authenticate, against
the directory service. But as it currently stands no TLS is configured or
enforced meaning passwords will be transmitted in the clear, as well as any
other LDAP query.

Quite a few people will argue that since directory services are usually not
exposed to the outside world but instead only accessible through an internal
network this doesn't matter much. I disagree, b/c I don't trust the network
to provide a security boundary. If anyone manages to eavesdrop on that
connection, for nefarious reasons or not, any credentials that are transferred
are compromised. As such I set up my services to assume they're operating
on and over the internet, making TLS a requirement.

## Table of contents
* [Table of contents](#table-of-contents)
* [Two modes of TLS](#two-modes-of-tls)
* [Getting the certificates](#getting-the-certificates)
* [Configuring TLS](#configuring-tls)
    * [`ldaps://`](#ldaps)
    * [TLS version and cipher suite](#tls-version-and-cipher-suite)
    * [Require STARTTLS for `ldap://`](#require-starttls-for-ldap)
* [Next up](#next-up)

## Two modes of TLS

There are two ways we can enable TLS. The `ldaps` protocol uses a separate port,
636, and requires TLS to be established before any further communication with a
directory service can take place. This is often referred to as implicit TLS.

Additionally, we can request TLS for our regular connections on port 389 using
the STARTTLS mechanism. This works by first establishing a plain connection and
then upgrading that to a TLS encrypted connection. This can be referred to as
explicit TLS, since we have to explicitly ask the server to do this.

I would recommend enabling both. Some pieces of software really don't like the
`ldaps` protocol for some reason, so having the fallback of `ldap` over 389
with STARTTLS can be very helpful.

## Getting the certificates

Before we can enable TLS at all we'll need to get a certificate for this
server. How you do this varies wildly on your environment. I'm going to assume
you know how to get these certificates for your environment. Personally I use
[Lets Encrypt](https://letsencrypt.org/) for mine.

Once you have the certs you'll need to place them somewhere the slapd process
will be able to read them. I chose `/etc/openldap/ssl`. Ensure the actual
certificate, private key (and chain file) have a restrictive set of permissions
applied to them (I use `0400`) and are owned by the UID that slapd runs as.

Take note of both the path and the file names, we'll need them in a minute.

## Configuring TLS

We need to start with telling the directory service where it can find the
TLS certificate and private key. In order to do this you'll need the following
ldif, adjust as necessary:

```ldif
dn: cn=config
changetype: modify
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/openldap/ssl/chain.pem

dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/ssl/cert.pem

dn: cn=config
changetype: modify
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/ssl/key.pem
```

The `olcTLSCACertificateFile` should contain the root CA and any intermediary
CA, in order to get the full chain of trust. `olcTLSCertificateFile` is the
public certificate and `olcTLSCertificateKeyFile` is the private key.

### `ldaps://`

With the certificate configuration in place all it takes to enable `ldaps`
is to pass that as an argument to `slapd` when starting the service:

```sh
/usr/bin/slapd <options> ldap:/// ldaps:///
```

Now you can connect to your directory service over port 636 with TLS. In
Apache Directory Studio, edit the connection and instead use "Use SSL
encryption (ldaps://)" for the "Encryption method" and adjust the port
accordingly.

### TLS version and cipher suite

Before we go on with enabling the STARTTLS variant we should take a moment to
further configure some aspects of TLS.

Most notable is that right now the directory service will allow you to use
old protocol versions, such as SSL 3.0, and old/vulnerable cipher suites. This
is undesirable and easily fixed.

Lets start with requiring a modern version of TLS, TLS v1.2 or higher:

```ldif
dn: cn=config
changetype: modify
replace: olcTLSProtocolMin
olcTLSProtocolMin: 3.3
```

You can change the value of `olcTLSProtocolMin` to `3.2` for TLS v1.1 or
higher and `3.1` for TLS v1.0 or higher.

Next up we should require a modern and strong set of ciphers. This is where it
gets complicated. The cipher suite is configured using `olcTLSCipherSuite` but
the value you put in there depends on whether OpenLDAP was built with GnuTLS
or OpenSSL/LibreSSL etc.

On Alpine it's built with LibreSSL, so we can use something like [Mozilla's
SSL Configuration Generator](https://mozilla.github.io/server-side-tls/ssl-config-generator/)
to help us out. If you're on a distrubtion that built it with GnuTLS, like
Debian and Ubuntu, you'll have to look up what the GnuTLS cipher suite
string looks like.

In my case, I applied this:

```ldif
dn: cn=config
changetype: modify
replace: olcTLSCipherSuite
olcTLSCipherSuite: ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256
```

### Require STARTTLS for `ldap://`

With all of that in place I now want to require the use of STARTTLS over port
389 when querying the directory service. This will essentially disallow plain
text communication.

Doing this requires one more change to be applied:

```ldif
dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcSecurity
olcSecurity: tls=1
```

What this does is say that "any access to the mdb database" (that's the DIT),
requires a connection that is protected by TLS. With this in place it's no
longer possible to query our directory service using an unsecure connection.

`olcSecurity` can be used to place additional requirements on the Security
Strength Factor. [Zytrax has some documentation on that over here](http://www.zytrax.com/books/ldap/ch6/#security).

## Next up

With all of this in place you can now securely communicate with a directory
service. However, this does nothing to limit what someone can do with a
directory service. For that, we'll need to [start writing ACLs](/2018/10/27/ldap-writing-testing-acls).
