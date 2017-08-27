---
layout: post
title: "Go's zero values and (de)serialising"
categories: go
---

As you might've noticed from other blog post entries I'm suddenly all into
directory services. This happens b/c that's what I'm currently working on.
As such I find myself needing to manipulate data in a DIT quite a bit and
writing ldif's by hand is not my idea of fun. Instead I set out to create
a small library that would essentially allow me to parse the result of
LDAP search result entries into a Go struct and transform those back into
add or modify operations.

The LDAP library I use is [go-ldap](https://github.com/go-ldap/ldap) and it
provides most of the basic building blocks. `Search()` takes a `SearchRequest`
which returns `Entries`, a list/slice of `Entry` structs. However, all these
`Entry` objects' values are strings (even though they're not necessarily so)
and manipulating `Entry` itself is a bit annoying. It's also entirely possible
that I need to create a new `Entry` based on getting data from somewhere, like
a user provisioning system.

I wrote some code that basically allows me to do this instead:

```go
type User struct {
  DN string
  CN string `ldap:"cn"`
  Username string `ldap:"uid"`
  Mail []string `ldap:"mail"`
  ...
}

for _, entry := range searchRequest.Entries {
  err := ldap.Unmarshal(entry, &User{})
  // handle err
}
```

I can now create regular Go structs and using struct tags specify which
attribute maps to what field and what the type is (multivalued fields are
stored in a slice). This should be very familiar to anyone that's ever
done some JSON encoding/decoding into structs in Go. Like the standard
library's `encoding/json` I rely heavily on `reflect` to transform everything
into the right types, which in itself took me a few hours and lots of
frustration to get right.

Similarly, I can encode my user back into an `Entry` along these lines:

```go
u := User{
  DN: "uid=daenney,ou=people,dc=bubblegbum,dc=com",
  CN: "Daenney",
  Username: "daenney",
  Mail: []string{"daenney@bubblegum.com"}
}

entry, err := ldap.Marshal(u)
// handle err
```

It also allows me to build helpers like `ToAddReq` that will take my struct
and generate an `AddRequest` which I can then `Add()` to a server.

This becomes very useful when you want to do ETL (extract, transform, load)
type of actions between directory services, b/c you're migrating environments
or changing schemas. For example, I can do this:

```go
type User struct {
  DN string
  CN string `ldap:"cn"`
  ...
}

type LegacyUser {
  User
  CostCenter int `ldap:"postalCode"`
}

type NewUser {
  User
  CostCenter int `ldap:"constcenterId"`
}

for _, entry := range sr.Entries {
  l := &LegacyUser{}
  err := ldap.Marshal(entry, l)
  // handle err
  u := &NewUser{}
  copier.Copy(l, u) // Copy the LegacyUser into a NewUser, essentially setting all the same fields
  u.ToAddReq()
}
```

This is a pretty neat trick. Since the field on both `LegacyUser` and
`NewUser` is called `CostCenter` the [copier.Copy](https://github.com/jinzhu/copier)
will make `NewUser` have that field set too. But when calling `ToAddReq()`
or `Marshal()` on it, it'll get serialised based on the struct tag, so
`costcenterId` and not `postalCode`.

## Zero values

However, a problem now arises. When doing Add or Modify requests, you're
supposed to only set fields for a DN that are actually set or modified. So what
we don't want to do is have a add or modify operation that happens to set
a field to an empty string (the zero value of a string), it should just not
set that field as part of the add or modify. We want to omit "empty" fields.

Lets look at our user struct again:

```go
type User struct {
  DN string
  CN string
  Username string
}
```

When you create a new object all three fields will be initialised to their
zero value, the empty string. Here the job is easy enough, if you get an
empty string you omit the field when `Marshal`ing it or when generating
the `AddRequest` or `ModifyRequest`. The empty slice is similarly easy
to deal with. Essentially they imply `omitempty` when serialising.

However, integer is a problem. Lets say we have a field that keeps track
of failed authentication attemps too:

```go
type User struct {
  FailedAttempts int `ldap:"failedAuthenticationAttempts"`
}
```

Now once we `Unmarshal()` we will no longer be able to distinguish between
having had 0 failed attempts and the field not having been set in the first
place, as the zero value of `int` is `0`. This might not seem super
critical, this specific field not being set kind of implies you haven't had
any authentication failures but it might be relevant in other places. It's
also annoying when you're trying to diff two structs where in one place
the value could have been explicitly set to `0` but in the other you're
looking at the zero value.

This becomes really annoying in a number of places and the common way to
solve it is to use a `*int` instead. Then when it was unset it'll be `nil`
instead of `0`. You can do the same thing with `*string` and `*bool` for
example. Sounds easy enough but needing to create pointers to
integers all the time is a bit annoying for your end users. So you end up
adding something like `ldap.Int()` instead which handles it for you:

```go
type User struct {
  FailedAttempts *int `ldap:"failedAuthenticationAttempts"`
}

u := &User{}
// somewhere during Unmarshal
// check if the failedAuthenticationAttempts field was returned with a
// non-empty value and then set it to value
u.FailedAttempts = ldap.Int(value)

// Or when creating a new user:
u = User{UID: ldap.Int(1337)}
```

Besides the fact that this is not super elegant we now have pointers to
slices, strings, ints etc. hanging around that's bound to put
more pressure on the garbage collector. It probably doesn't matter but
once you're dealing with thousands of entries it feels iffy. The other
option is to use some library that provides an Optional version of the
types you need. But it suffers from similar API ickyness. It essentially
forces the consumer of your library to be or become aware of an implementation
detail of the language. You'll have to ensure in your documentation that
this is explained to them and why it's important that they now use your
custom `ldap.Int`, `ldap.String` and `ldap.Bool` types. It's not an
awesome experience and for anyone relatively new to Go it's pretty
confusing.

Another option, equally icky, is to define a value for the field that is
invalid. For example the `gidNumber` and `uidNumber` can be 0 (hello root)
but never negative. So when it's unset you could set it to `-1` during the
Unmarshal and then explicitly deal with it in the different methods that
transform your structs. This is mostly surprising to consumers and they'll
have to know that when they're creating an object for which they want that
integer field to not show up in the `Entry`, `AddRequest` or `ModifyRequest`
that they'll have to set it to this special value. Because of this your
consumers will now need to do "magical value" checks which is not
an improvement.

If you've done much with JSON encoding/decoding you've probably ran into
this issue too. The GitHub API client and the protobuf implementation for
Go all use the pointer trick to work around this issue, but it comes with
a cost. It also means that anyone consuming your deserialised object will
now have to do explicit nil checks before doing anything with the value
of a field, or suffer runtime panics.

I would really like for Go to have a built-in solution to this issue that
doesn't require pointer juggling. In 9 out of 10 cases the zero value
is exactly what I want but when (de)serialising things sometimes being
able to distinguish between the zero value and unset is important.

There is a proposal in the form of [sum/discriminated union](https://github.com/golang/go/issues/19412)
types that, as far as I can understand, could potentially solve this in
the future.
