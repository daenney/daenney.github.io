---
layout: post
title: "Directory Services 101: Designing the DIT"
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

I apologise for the long delay between posts. Life took over for a while
and I never got around to writing the rest of it.

Sitting down and thinking a bit about the DIT upfront can save you endless
hours of furstration later on.

There's few rules as to what to do and what not to do and lots of contradictory
advice on the topic. This is my set of rules:

* Do NOT model organizational hierarchy as container types
  (i.e organizational units). Organizations are living organisms, they change
  and restructure regularly. You don't want that kind of churn as it will
  cause the DNs of all kinds of objects to change with it.
* Ensure DN's remain static for the lifetime of an object. This goes hand in
  hand with the above. Once a user object is created, their DN should not
  change. Same goes for any object. This ensures you can always and correctly
  refer to an object the same way and avoids all kinds of complications with
  external systems that might sync information from LDAP into a local
  database.
* Define what objectClasses entities under a specific part of the tree should
  have. This ensures that everyone in an organizational unit has the same set
  of objectClasses, avoiding all kinds of nastiness if you need to do programatic
  things on part of a hierarchy.
* Never, EVER EVER, allow or use `extensibleObject`. Adding it on an entity
  allows you to pick and use any attribute from any objectClass, without
  declaring that you use it. Essentially, attributes become invisible, you have
  to know that an attribute is available on an entity despite the objectClass not
  being there. All the useful stuff that you get by having a well defined
  entity with set objectClasses goes out the window.

This generally means that I structure a DIT like this. Adapt it to your needs,
this is not set in stone:

* `dc=example,dc=com`, the root.
* `-| cn=admin`, an `organizationalRole` whose members are granted `manage` level
  access to everything in this DIT (more on ACLs later).
* `-| ou=example`, an `organizationalUnit` with the name of the company or group.
  I usually reuse one of the `dc`'s. I do this to ensure that if I ever need to
  combine multiple DITs together, I can root all objects at different pahts. Kinda
  how you'd have a host like example.com with /login, /about, /contact etc.
* `---| ou=people,ou=accounts`, accounts for human beings, usually `inetOrgPerson`
  with `posixAccount` and `shadowAccount`.
* `---| ou=robots,ou=accounts`, accounts for system/applications, usually
  `organizationalRole` (this is not entirely semantically correct, but it's the
  smallest object I could find that gives me the `cn` attribute) and
  `simpleSecurityObject` (so I get access to `userPassword`).
* `---| ou=groups`, groups for either systems, humans or both, `groupOfNames`
  paired with `posixGroup` when necessary. One thing to note here is that if you
  run a regular OpenLDAP server without having loaded the RFC 2307bis schema, you
  won't be able to pair a `posixGroup` with a `groupOfNames` as they are both
  `STRUCTURAL` in that case. Most other directory services default to, or allow
  you to configure, the use of RFC 2307bis.
* `---| ou=userPrivate,ou=groups`, *nix [User Private Group][upg]s, one exists
  for every account in `ou=people,ou=accounts`.

As you can see no organizational structure is encoded in here. A user who starts
in finance isn't creted in `ou=Finance`, which would make that `ou` part of their
`DN`. Instead, they're just `uid=$username,ou=people,ou=accounts,ou=example,dc=example,dc=com`
and no matter what role they have in the company, you can always universally refer
to their account that way.

## Encoding organizational structure

So how do you represent organizational structure? There's a multitude of ways you
can do this.

You could have something like this:
* `ou=Finance,ou=deparments,ou=exampl,dc=example,dc=com`
* `-| ou=some_sub_department,ou=Finance,...`

However, the user accounts can't exist in multiple parts of the tree, so the lowest
level you'll end up with has to be a `groupOfNames` or an `organizationalRole`, so
you can make them members of that entity.

I personally prefer to solve this with nested groups. Most systems support this
nowadays so instead I have something like this:

* `| ou=groups,ou=example,dc=example,dc=com`
* `-| cn=finance,ou=groups,....`, a `groupOfNames`
* `-| cn=some_sub_department,ou=groups,...`, another `groupOfNames`

Then I make `cn=some_sub_department` a `member` of the `finance` department. You
can choose to add users, groups or both at either level. Now if you want to know
who's in finance you fetch `cn=finance` and walk the tree, resolving all the
members.

Using groups has some other neat features, like being able to use the `owner`
attribute for example to encode who 'owns' this resource, a department head for
example.

One thing to be mindful of when taking this approach; you need to ensure you
don't create cyclic memberships. Essentially you want your DIT to be a [Directed
Acyclic Graph][dag]. Even if you don't go for nested groups, this is a good
thing to enforce.

Using nested groups isn't terribly human friendly if you expect admins to be
doing a lot of manual work in your DIT. The design here is very much geared
towards assuming the lifecycle of most entities will be governed by automation.
Storing the data in a directory service is largely an implementation detail
(with some bonus features like easy integration with lots of enterprise software).

## Roles or positions

Sometimes it's useful to have a way to represent roles, say a group of managers,
engineers, an auditor or a financial controller. Often these can just be
represented as a `groupOfNames` but I like keeping formal roles in a separte
part of the hierarchy, say `ou=roles,ou=example,...` with `organizationalRole`
entities instead. These could also be `groupOfNames` instead and they probably
should be if you intend to use these groups as access control groups for a
system. I would recommend not doing that and keep access groups for systems or
services entirely separate, represented by groups in `ou=groups`. Ideally
depending on the role you have you'll automatically be made member of certain
groups. This separates "who you are" from "what you have access to" and makes
it easier to have much more flexible access rules that are composed out of
different roles and other things.

Underneath roles it can be useful to mimick organizational structure, so you can
have the different business units, departments and what not in there. This makes
it pretty easy to be able to answer questions like "who's the head of HR" by
getting `cn=lead,ou=HR,ou=roles,ou=example,...` or "who are
managers in R&D"by looking at `cn=managers,ou=R&D,ou=roles...` etc.

These roles would need to be maintained by automatic tooling, that takes care
of the lifecycle of these entities. It should probably be kept in sync automatically
with your payroll software, or be the thing that drives it.

[upg]: https://security.ias.edu/how-and-why-user-private-groups-unix
[dag]: https://en.wikipedia.org/wiki/Directed_acyclic_graph
