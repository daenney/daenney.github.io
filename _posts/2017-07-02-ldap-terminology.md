---
layout: post
title: "Directory Services 101: terminology"
categories: tech
---

This post is part of a series on directory services. Current available
installments are:

* [Introduction](/2017/07/02/ldap-terminology.html)
* [Terminology](/2017/07/02/ldap-terminology.html)
* [Basic concepts](/2017/08/26/ldap-basics.html)
* [Designing the DIT](/2018/10/26/ldap-designing-dit)
* [Setting up an LDAP server](/2018/10/27/ldap-server-setup)
* Securing your LDAP server
* Writing and testing ACLs

---

Directory services come with a lot of terminology and part of that lingo is
what makes things difficult to understand to someone who hasn't heard any
of it before.

Below is a common list of terms you might run into in documentation and the
rest of these posts and hopefully a simple enough explanation of what they
mean. This list is meant as a reference. If you ever get stuck in a blog post
or reading some of the documentation, hopefully this'll help.

* **X.500**: The standard, nowadays maintained by ITU-T and unhelpfully locked
  behind a paywall
* **Directory server**: A server hosting a directory (the database)
* **Directory service**: A service providing the ability to query and/or modify
  the directory
* **LDAP**: The **L**ightweight (ahem) **D**irectory **A**ccess **P**rotocol is
  what usually powers the communication with a directory service. A lot of times
  people refer to directory services as LDAP and the database as the LDAP server
* **DIT**: The directory information tree, a hierarchical tree-like representation
  of entries in the directory service. I find it helpful to visualise this as a
  set of folders that can contain other folders or files
* **Entry**: An entry in the directory representing an actual thing, such
  as me the person or my desktop (and not the abstract concept of a person or
  a desktop, think of it as an instance vs. an object)
* **DN**: A distinguished name, essentially a lookup key uniquely identifying an
  entry in the DIT
* **RDN**: A relative distinguished name, a lookup key uniquely identifying an
  entry in the DIT relative to its parent
* **Base DN** or **suffix**: A DN pointing to the root of your tree. Usually
  searches for objects are done relative to the base DN and client tools can be
  configured to do so. Any object returned allows contains the full DN, including
  the suffix. You'll often see it in the form of a DNS name split into labels,
  such as `dc=example,dc=com`
* **Bind DN**: When authenticating to a directory service to perform an action
  we **bind** onto an entry that gives us the permission to perform this action.
  Very often the bind DN is the DN to your user but it can be a service account
  or another security entry
* **OID**: The object identifier, an identifier mechanism standardised by ITU
  and ISO/IEC for naming something with a globally unique, unambiguous and
  persistent name. A dot-separated sequence of integers like 1.3.6.1.4. etc.
  and so forth and so on
* **attribute**: A key-value pair that can be set on an entry. Attributes also
  define their type and how they can be matched or searched against, for
  example if the attribute is a string and supports substring matching.
  Attributes are assigned an OID
* **objectClass**: a collection of required and optional attributes to help
  model an entity, such as a person, an account, a computer etc. Like
  attributes every objectClass is identified by an OID. objectClasses can
  inherit from each other
* **Schema** A collection of attributes and objectClasses. A directory service
  can be powered by multiple schema. A schema can define the same attributes
  and objectClasses as another schema but can then not be loaded at the same
  time

If anything is missing or needs to be corrected feel free to send a PR on
GitHub.
