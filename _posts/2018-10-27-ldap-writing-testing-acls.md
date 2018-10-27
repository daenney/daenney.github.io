---
layout: post
title: "Directory Services 101: Writing and testing ACLs"
date: "2018-10-27 15:00:00"
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

ACLs, access control lists, are an important aspect of running a directory
service. ACLs are how you control who can access which parts of the DIT and
what things they can do. You can limit certain things like which attributes
one can read or write. This also enables you to write ACLs that allow users
to update certain of their own attributes, say their `displayName`, allowing
a form of self-management.

## Table of Contents

* [Table of Contents](#table-of-contents)
* [Structure of an ACL](#structure-of-an-acl)
    * [what](#what)
        * [Part of the tree](#part-of-the-tree)
        * [Filter](#filter)
        * [Attributes](#attributes)
    * [who](#who)
        * [Group of groups](#group-of-groups)
    * [ssf](#ssf)
    * [level](#level)
    * [control](#control)
* [Evaluation of ACLs](#evaluation-of-acls)
* [Applying ACLs](#applying-acls)
* [Testing ACLs](#testing-acls)
* [Other resources](#other-resources)

## Structure of an ACL

ACLs in OpenLDAP look pretty much like this:

```text
access to <what>
    by <who> <ssf> <level> <control>
```

This looks simple but can get complicated pretty fast. I'll take each section
and elaborate on it further.

When using online/dynamic configuration the `access` keyword is omitted, as
ACLs are stored in the `olcAccess` attribute.

### what

The `<what>` can be split up into three pieces: `<part of the tree>`, `<filter>`,
and `<attributes>`.

#### Part of the tree

The first one, `<part of tree>` allows you to qualify to
which part of the tree this applies. If it should apply to everything a
value of `*` can be used. It could for example be `dn.subtree="dc=example,dc=com"`
for an ACL that will apply to `dc=example,dc=com` and all entries below it.

#### Filter

The filter can be used instead of the `<part of the tree>` or as a complement
to it. It has to be specified according to the LDAP search filter format.

When `<part of the tree>` is not omitted, the `<filter>` is optional but
can be used to specify a precondition. It can be used to gate access to an entity
based on if it has an attribute with a specific value. For example:
`filter=(status=active)`. This could be used to implement a form of read-only
entities in a part of the DIT, for example employees that have left the company,
so that those can only be updated by an administrator instead.

#### Attributes

`<attributes>` lets you specific if this ACL is limited to certain attributes.
I could write a rule that gives someone the ability to write the `displayName`
attribute but not the `uid` attribute: `attrs=displayName,givenName`.

### who

The `<who>` allows you to specify who this ACL applies to. It's often
a DN, for example: `group.exact="cn=admin,dc=example,dc=com"`. This would allow
any DN listed in the `member` attribute of the group the level of access defined
by the ACL. When using `group.exact` OpenLDAP knows that it should look at the
`member` attribute to find the DN.

In our case though `cn=admin` is not a *groupOfNames* and as such
does not have `member`s. Instead it's an *organizationalRole* so we'll need to
change it to: `group/organizationalRole/roleOccupant="cn=admin,dc=eample,dc=com"`
instead. You can do some really clever stuff with this one too. For example, the
*inetOrgPerson* has a *manager* attribute which should be the DN of whomever
this person reports to. Using that in the who part of the ACL allows you to set
up the directory service in such a way that someone's manager could manage
part of their reportees attributes, like which groups they are a member of.

You'll probably have spotted the `group.exact` here, meaning only the group
that matches the DN exactly. Sometimes you might want to grant access to any
group from a certain part of the tree, in which case you could use something
like `group.base="ou=groups,ou=example,dc=example,dc=com`.

There are also a few special values for who; `*`, meaning anyone (authenticated
or not), `anonymous` (unauthenticated), `users` (authenticated) or `self` (user
associated with the entry). `self` is useful in order to let you write an ACL
that says "users can manage these attributes on themselves, but not on someone
else". Using `*` or `anonymous` would allow an unauthenticated user access,
so use this with caution. In general I'd recommend to never use it and always
require authentication when interacting with your directory service.

#### Group of groups

I just showed you how you can use `group` or `roleOccupant`, but by default
that match is not recursive. Meaning that if the `member` of the `group.exact`
is a DN that points at another group instead of a user, nobody who's a member
of the nested group will be granted access.

In order to get around that you need to expand the members, essentially do a
recursive lookup. The way that is done is by using a `set` instead.

```text
access to *
    by set="[cn=admin,dc=example,dc=com]/roleOccupant* & user" manage
```

The `roleOccupant*` means "recursive expand *roleOccupant*". The `& user` means
"check the authenticated user's DN against it". If the result of this
operation is non-empty, meaning the authenticated user's DN matched at least
once while expanding `roleOccupant` recursively, they are granted access.

Note that any entity mentioned in the `roleOccupant` attribute of `cn=admin`
has to be either a user or another entity with a `roleOccupant` attribute.
This means that if you put a *groupOfNames* in there which has a `member`
attribue instead it won't look those up and the `& user` won't match, resulting
in an empty set and therefor access being denied.

### ssf

The `<ssf>` allows you to specify a Security Strenght Factor that needs to be
met for this ACL to apply. For example, `tls=256` to ensure that this ACL only
applies when a TLS connection negotiated with a 256 bit key. It's rare to see
these.

### level

The `<level>` is the last one, and can be one of `none`, `disclose`, `auth`,
`compare`, `search`, `read`, `write` or manage. These form a chain, so `manage`
implies everything beneath it. In practice it's rare to see `disclose`,
`compare`, or `search`.

Every ACL ends with an implicit `by * none` who clause, disallowing access when
nothing matches.

You'll typically see `read`, `write` and `manage` used the most. `auth` is
interesting and usually paired with `anonymous` in one specific case:

```text
access to attrs=userPassword
    by self write
    by anonymous auth
```

The `by anonymous auth` is necessary so that during an authenticatin, a BIND,
the server is allowed to read the (hashed) password stored in `userPassword`
and compare against the one provided in the BIND operation. Using `by self write`
means that once authenticated they're allowed to change their own password.

### control

The `<control>` influences the evaluation of the ACLs, which we'll discuss
in the next session. For now keep this in mind: it defaults to `stop` if
omitted, and can be set to `continue` or `break`.

## Evaluation of ACLs

By default these rules apply:

* Only the first `what` that matches is considered
* Within a `what`, only the first `who` that matches is considered
* If nothing matches, no access is granted as it matches the implicit
  `by * none stop`

Essentially it means that the evaluation of an ACL will stop on the first
match, even if multiple could apply. Therefore, the ordering of the `what`
and `who` clauses affect the access granted.

Getting around that means changing the `<control>` part of an ACL. When
evaluating the `who`'s of a `what`, if you specify a control value of
`continue` the next `who` clause for this `what` will also be considered.
If it matches the access level will be `AND`ed with previous matches.

This still only lets you take into account multiple `who` clauses, but
perhaps multiple `what` clauses also match. In that case setting the
control value to `break` will cause it to evaluate other `what`'s too.

These rules, and how you can affect them by changing the control value, is
what makes writing ACLs for OpenLDAP rather tricky and error prone. A
simple logic mistake could lock even an administrator out of the system.

As such it's usually helpful to ensure you have an ACL like this in place
as the first ACL:

```text
access to dn.subtree="dc=example,dc=com"
    by group/organizationalRole/roleOccupant="cn=admin,dc=example,dc=com" manage
 ```

Assuming you're a member of `cn=admin`, no matter how you screw up the ACLs
you'll always retain full administrative access to the DIT.

## Applying ACLs

`cn=config` is where the configuration of the directory service itself is
stored. This is separate from the DIT with all your entities, and when
connecting to the directory service you'll have to specify `cn=config` as your
base DN.

You can do this in Apache Directory Studio by unchecking the "Get base DNs from
root DSE" and specifying a "Base DN" of `cn=config`. Note that only `cn=Manager`
has access to `cn=config` so you might need to update the settings in the
"Authentication" tab too.

In order to set ACLs we need to modify the `olcAccess` attribute on the
`olcDatabase` entries underneath `cn=config`. To set ACLs that control access
to the DIT you'll have to modify `olcDatabase={X}mdb`. The `X` will be `2` in
the case of the configuration generated by slapddgen but it can vary per
environment.

In order to grant additional people access to `cn=config` itself you'll have
to update the `olcAccess` on `olcDatabase={0}config`. Be really careful when
doing that. If you botch this one and lock all the admins out you're in for
a world of hurt.

`olcAccess` is multivalued, but since the order matters for the ACL evaluation
they're prefix by a `{X}`, where `X=0` is the first entry/highest priority
and so on.

Slapddgen will have generated a few ACLs for you, so you should see this:

```text
{0}to dn.subtree="dc=example,dc=com" by group/organizationalRole/roleOccupant="cn=admin,dc=example,dc=com" manage by * break
{1}to attrs=userPassword by self write by group.exact="cn=readSecret,ou=groups,ou=example,dc=example,dc=com" read by anonymous auth
{2}to attrs=sn,displayName,mail,givenName,initials,mobile,preferredLanguage,title,telephoneNumber by self write by users read
{3}to dn.subtree="dc=example,dc=com" by users read
```

Lets break that down. The first entry specifies that anyone who's listed as
a *roleOccupant* of `cn=admin,...` gets the `manage` level of access on
everything from the base DN onwards. This is the highest level of access,
meaning they can read and write everything.

You'll see that at the end of the line I have a `break` there. That's
because I have a second entry pertaining to `dn.subtree="dc=example,dc=com"`
granting all (authenticated) users `read` access. I could not do this and
simply have a second who clause of `by users read`. Mind you though that
if you do that ACL 1 and 2 would never get evaluated unless we added a
`break` to it too. This is why things can get complicated, fast.

ACL 1 and 2 are largely there for self-management. `userPassword` can be
updated by oneself, accessed by anonymous for authentication purposes and
read by a special `readSecret` group. This group doesn't necessarily exist
but it's an example of how you could grant access to such an attribute to
all members of a specific group.

ACL 2 gives oneself the ability to update a number of administrative
attributes on their own *inetOrgPerson* entity and lets everyone else
read those values. This makes for a handy telephone book.

Notice how ACL 2 explicitly specifies `by users read`. That's necessary
since otherwise any other user wouldn't be able to read those attributes,
despite ACL 3 because by default we'd never get there. We could omit that
and instead do `by self write break` which should ensure we continue
reading the ACLs, end up at number 3 and gain read access. Feel free to
test this out.

## Testing ACLs

This is where it gets really annoying. In order to test an ACL you
basically have to authenticate as the `who` thats supposed to get access
to the `what` and verify you have access to it, and haven't lost access
to any other `what`.

This is a rather error prone process and the consequences of getting it
wrong in produciton can be rather annoying. Therefore, don't test this
in production!

Using [slapddgen][gen] and some seed files you can easily create a testing
copy of your directory service and have at it. If you get it wrong all
you need to do is restart the container and you've got a clean slate.
Once you're satisfied with the changes, apply them to production.

Thankfully we can apply some automation to this! I use [pytest][pt] for this,
paired with [pytest-docker][ptcoker] and the [ldap3][ldap3] library.

Using pytest and ldap3 I can write tests against a "real" directory
service. pytest-docker is responsible for spinning up a Docker container
with my directory service and spinning it down at the end of the test
run.

Leveraging pytest and [pytest-datadir][ptdata] I can load the seed files from
the tests directory and apply them to the directory service using the
ldap3 library. Once that's done I can use the ldap3 library to execute
queries against the directory service allowing me to validate ACLs.

When you combine this with pytest's [fixtures][ptfix] it becomes very easy to
write tests that do a cycle of "modify directory service, check if
everything still works, revert changes" and move on to the next test.

## Other resources

There's a lot more resources on ACLs in OpenLDAP:

* Zytrax's [LDAP for Rocket Scientists][zytrax]
* OpenLDAP [Faq-o-Matic on Access control][faq]
* Access Control in the [OpenLDAP Administrator Guide][admin]
* [Keeping your sanity while designing OpenLDAP ACLs][aclblog]

[zytrax]: http://www.zytrax.com/books/ldap/
[faq]: http://www.openldap.org/faq/data/cache/189.html
[admin]: https://www.openldap.org/doc/admin24/access-control.html
[aclblog]: https://medium.com/@moep/keeping-your-sanity-while-designing-openldap-acls-9132068ed55c
[gen]: https://github.com/daenney/slapddgen
[pt]: https://docs.pytest.org/en/latest/
[ptdocker]: https://github.com/AndreLouisCaron/pytest-docker
[ldap3]: https://pypi.org/project/ldap3/
[ptdata]: https://github.com/gabrielcnr/pytest-datadir
[ptfix]: https://docs.pytest.org/en/latest/fixture.html#fixture-finalization-executing-teardown-code
