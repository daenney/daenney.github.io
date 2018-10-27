---
layout: post
title: "Directory Services 101: the basics"
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

Directory Services are fundamentally pretty simple. All information they
contain is stored in a hierarchical tree structure, called the DIT. Within
the DIT entries can be nested into or beneath each other, creating this
tree-like structure.

Anything that you can describe in terms of objectClasses can be stored in the
DIT. It's therefor not limited to just users, groups and computers though
that is usually what people start with. But you can store all kinds of things,
like office locations, floors in a building, meeting rooms, mailing lists,
printers etc. etc.

Since all you need to describe things in the DIT is a schema with the
necessary attributes and objectClasses to do so you can create your own schema
if nothing already exists that can help you out. Writing your own attributes,
objectClasses and schema's is a pretty advanced topic though and something I'll
try to cover later.

## Entries and objectClasses

An entry in the DIT can have multiple objectClasses defining it, or a
single one that inherits from a chain of other objectClasses. There exist 3
types of objectClasses:

* ABSTRACT: few objectClass of type abstract exist. The one you'll most likely
  run into is *top*. *top* is the root object of sorts and is usually said to
  'terminate the hierarchy'. Think of it as `java.lang.Object` or Python's
  `object`. It's there, everyone has it but you pretty much never think about
  it.
* STRUCTURAL: when an objectClass is of the structural type it can be used to
  create entries with. Every entry can only have 1 structural objectClass
  though that structural class can inherit from other structurals. If you try
  and create an entry with two distinct structural objectClasses you'll get an
  error.
* AUXILIARY: a type of objectClass that can be added to an entry. An entry will
  usually consist of one STRUCTURAL and many AUXILIARY classes.

A few common objectClasses you'll probably run into when modelling people are
*inetOrgPerson*, *organizationalPerson* and *person*. These are all structural
but supplement each other (i.e they form a chain of inheritance). The most
specific one is *inetOrgPerson* that defines a number of additional attributes
on top of *organizationalPerson* which in turn extends *person*. If these
people need access to Unix systems you'll likely also encounter *posixAccount*
and *shadowAccount*, both of which are auxiliary.

For groups you'll likely run into *groupOfNames* and *posixGroup*. Both of
these are structural in the original RFC 2307 that defined them but do not
suplement each other. This is a fairly annoying limitation because a
*groupOfNames* is essentially what you want to use to bundle a group of
entries together in a logical unit, but without also being a *posixGroup*
you'd have to do some double bookkeeping to also create a group allowing
that same set of users to login to Unix systems. A proposed but never
ratified update, RFC 2307bis, changes this and turns *posixGroup* into
an auxiliary and allows for the `memberUid` attribute to be empty, i.e
groups are allowed to not have members. Though RFC 2307bis never became an
official RFC plenty of directory services use it and support it. Another
group-like object is *organizationalRole*.

## Schema

A schema is a collection of objectClasses, and therefor also attributes. It
is not quite the same as a database schema. For example, a schema in the LDAP
sense doesn't define a table "users" and its columns (or attributes), it just
defines that a number of classes and attributes exist to help you model a user,
and you can combine those classes in whatever way you see fit (as long as their
types are compatible).

Two people don't even have to have the same objectClasses, even if they're
stored at the same level in the DIT. For your and everyone else's sanity
though it's helpful to ensure that you always use the same set of objectClasses
to model a specific entity. In that sense directory services are much more like
document stores (NoSQL) than traditional databases (SQL RDBMS) so the term
schema can get a tad confusing.

Having these schemas provides us with a big advantage. The attributes within
a schema define all sorts of things about themselves, such as how they can be
named (`cn` but also `commonName` to refer to the same field), what their value
type is (string, integer, ...), being single or multi-valued, how we can match
against them (exact vs. substring vs. regexp etc.) but also how they can be
validated. For example you can't store a `-` in the `telephoneNumber` attribute
as that's just not a valid phone number. Essentially this provides us with a
type system of sorts for our entries plus data validators. This helps
tremendously to ensure we don't end up with all kinds of weird things on our
entries which in turn makes consuming them much easier. It's also a helpful
safety net when modifying entries.

All attributes in LDAP are by default multi-valued, i.e you can set them
multiple times on an entry. For example, a user can have multiple email
addresses so you can set `mail` multiple times. However, this doesn't make
sense for all attributes. If a group were to have multiple `gidNumber`s
identifying it things would get very confusing, so that attribute is single
valued.

## Hierarchy, DNs and RDNs

As I've said before the DIT is a hierarchical structure, a tree. It's very
common to root your tree based on a domain name. Lets say your organisation
is named "Bubblegum Inc." and ownes the `bubblegum.com` domain. This could,
doesn't have to be, the start of your tree.

To map this into our DIT we'd start with transforming the
domain name into domain components (`dc`), an attribute of the *organization*
container type. Doing so is very simple, split on the `.` and every label that
you get is a domain component. So you'd end up with your root being
`dc=bubblegum,dc=com`. This would also be your base DN or suffix.

In order to be able to reference objects in a DIT we need a way to point at them,
a lookup key of sorts. Every object has a DN, a "fully qualified" identifier
and an RDN, one that identifies them relatively to their parent in the tree.
The DN of an object always terminates with the base DN.

I find this is best explained with a file system layout as an example:

```text
/
└── people/
    └── daenney
```

The root of our filesystem is `/`. If I wanted to uniquely point at me
my DN would be `/people/daenney`. However, from within the `people`/ folder
my RDN is just `daenney`, as that uniquely identifies me in that part of the
hierarchy. From the perspective of the root of the tree my RDN is
`people/daenney`.

If this were an actual directory service the DIT would look something more like
this:

```text
.
└── dc=com
    └── dc=bubblegum
        └── ou=people
            └── daenney
```

In this case my DN would be `uid=daenney,ou=people,dc=bubblegum,dc=com` and my
RDN would be `uid=daenney` as seen from `ou=people`. Don't worry too much about
this representation just yet, just keep it in mind.

Remember that DNs and RDNs need to be unique. That's why for my user I'm
using the `uid` attribute and not something like the *Common Name* (`cn`)
which isn't necessarily unique. It can be made unique by appending something
like an additional identifier (an integer) but I find `uid` does the job
nicely.

*organization*s domain components and *organizationalUnit*s are part of the
DN and so would other container types be that are often identified by a `cn`.
As such a user cannot be a member of multiple *organizationalUnit*s, these
would actually have to be different entries. Because of this groups and
organizational hierarchy are usually modelled through *groupOfNames* and
*organizationalRole*s, of which you can be a `member` or a `roleOccupant`,
instead of nesting *organizationalUnit*s or other types.

## Next up

Now that we've seen some basic parts of what make up entries in the DIT we need
to talk a bit about how to design a DIT. Getting this right or wrong can make
or break a directory services implementation and is an important part of
ensuring your setup will be able to grow as your organisation grows.
