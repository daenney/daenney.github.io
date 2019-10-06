---
layout: post
title: "BeyondCorp @ Home: OpenID Connect Provider with Dex"
categories: tech
---

In [a previous post][prev_post] I showed you how to setup Keycloak to provide
you with OpenID Connect and SAML capabilities. The problem with Keycloak is
is that's it's a pretty big beast, whereas most of the time we don't need all
the functionality. It's also tricky to run in a highly available fashion and
is annoyingly slow to start up.

In this post we'll drop Keycloak in favour of [Dex][dex], a small OpenID Connect
Provider that supports a number of backends including LDAP. If you don't need
SAML, I'd strongly suggest you go this way instead.

## Table of contents

* [Table of contents](#table-of-contents)
* [Installing Dex](#installing-dex)
* [Configuring Dex](#configuring-dex)
* [Configuring OpenResty OIDC](#configuring-openresty-oidc)
* [Conclusion](#conclusion)

## Installing Dex

[Dex][dex] is a Go binary. You can either download it straight from the project's
[releases][dexrel] page or run it in a Docker container.

If you run it as a Docker container you'll have to mount the configuration for
Dex into the container, using something like:

```sh
docker run --name dex -p 127.0.0.1:5556:5556 \
  -v /path/to/config.yaml:/config.yaml:ro \
  -v dex_data:/data:rw \
  quay.io/dexidp/dex:vX.Y.Z \
  serve /config.yaml
```

For this example we'll run Dex with the built-in SQlite3 backend (used to store
sessions etc.) hence the `dex_data` volume mount to ensure that persist. Dex can
also persist using Kubernetes CRDs, etcd, MySQL, Postgres or in-memory.

## Configuring Dex

A configuration for Dex looks like this:

```yaml
issuer: https://<DOMAIN>
storage:
  type: sqlite3
  config:
    file: /data/database/dex.db
web:
  http: 0.0.0.0:5556

connectors:
- type: ldap
  name: OpenLDAP
  id: ldap
  config:
    host: <LDAP_HOST>
    insecureNoSSL: false
    insecureSkipVerify: false
    bindDN: cn=dex,....
    bindPW: "STRONG_PASSWORD"
    usernamePrompt: Username
    userSearch:
      baseDN: ou=...
      filter: "(objectClass=posixAccount)"
      username: uid
      idAttr: uid
      emailAttr: mail
      nameAttr: displayName
    groupSearch:
      baseDN: ou=...
      filter: "(objectClass=groupOfNames)"
      userAttr: DN
      groupAttr: member
      nameAttr: cn

staticClients:
  - id: "CLIENT_ID"
    secret: "CLIENT_SECRET"
    name: "OpenResty OIDC proxy"
    redirectURIs:
      - "https://<DOMAIN>/auth"
```

## Configuring OpenResty OIDC

The configuration is very similar to what we did for setting up the [OIDC
proxy in the previous post][prev_oidc].

In `auth.conf` you'll want to change scopes to:

```lua
scope = "openid email profile groups offline_access federated:id"
```

The `federated:id` will get you access to the User ID as known by the
connector. In case of LDAP this will be my `uid` b/c that's what's
configured for `idAttr`. Without it all you get is the user name, in
my case `displayName`.

You'll also want to change the value of `$session_name` to something
new so we don't try to pick up on old session cookies and the
`$session_secret` too for good meassure.

Change the `X-Auth-Userid` and `X-Auth-Username` headers to get the value
from `res.id_token.federated_claims.user_id` instead.

## Conclusion

At this point everything should work exactly like before, with the
main difference that you'll be using Dex now to issue tokens and go through
the login and consent flows.

Once you've verified everything works you can safely shutdown Keycloak.

[prev_post]: /2018/10/27/beyondcorp-at-home
[prev_oidc]: /2019/10/05/beyondcorp-at-home-authn-authz-openresty
[dex]: https://github.com/dexidp/dex
[dexrel]: https://github.com/dexidp/dex/releases