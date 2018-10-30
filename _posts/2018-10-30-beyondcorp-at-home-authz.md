---
layout: post
title: "BeyondCorp @ Home: Authorization"
categories: tech
---

In [a previous post][prev_post] I showed you how to set
up a "Lite" version of a BeyondCorp style access layer for a home or startup
environment. The reason I called it lite is because though it does do full
authentication, it didn't have separate controls for authorization. Meaning
if you could authenticate you were authorized, I couldn't specify that for
certain endpoints you have to be part of a specific group or be granted a
certain role before you get access.

The reason for that is a limitation in the Oauth2 Proxy that I used, it just
doesn't know how to get that data from Keycloak, or what to do with it. If we
switch it out for [Keycloak Gatekeeper](https://github.com/keycloak/keycloak-gatekeeper)
though we gain much more fine grained authorization capabilities.

## Table of contents

* [Table of contents](#table-of-contents)
* [Design changes](#design-changes)
* [Gatekeeper](#gatekeeper)
* [Reconfiguring the monitor stack](#reconfiguring-the-monitor-stack)
* [Adding authorization](#adding-authorization)
* [Rate limiting](#rate-limiting)
* [Conclusion](#conclusion)

## Design changes

There is one downside to using Keycloak Gatekeeper; you have to proxy the
requests through it. We can't use the `auth_request` model I showed previously.

One additional constraint to keep in mind is that Keycloak Gatekeeper only has
one "upstream" URL. So if you're like me and you have different `location`
blocks in your nginx which `proxy_pass` to a variety of services on different
IPs and ports you'll need another intermediary layer.

We can use nginx again as that layer, so we still end up with 2 components, but
with an extra round of `proxy_pass`. I've also had some issues with Gatekeeper
not correctly propagating all headers it got in the request, leading to some
fiddling in nginx in the second proxy layer to get everything to work.

In the end we end up with this:

```text
+-----------------------+
|                       |
|       nginx:443       |
|                       |
+----------+------------+
           |
           |
           v
+-----------------------+
|                       |
|    gatekeeper:3001    |
|                       |
+----------+------------+
           |
           |
           v
+-----------------------+
|                       |
|      nginx:4181       |
|                       |
+----------+------------+
           |
           |
           v
+-----------------------+
|                       |
|     backend:port      |
|                       |
+-----------------------+
```

## Gatekeeper

The Gatekeeper can be run from Docker! You'll also need some configuration,
here's mine:

```yaml
discovery-url: https://sso.example.com/auth/realms/example
client-id: KEYCLOAK_CLIENT_ID
client-secret: KEYCLOAK_CLIENT_SECRET
listen: 0.0.0.0:3001
enable-refresh-tokens: false
redirection-url: https://example.com
encryption-key: VERY_SECRET_VALUE_OF_32_CHARS
upstream-url: http://127.0.0.1:4181
enable-token-header: false
enable-authorization-cookies: false
enable-refresh-tokens: true
enable-login-handler: true
http-only-cookie: true
cookie-access-name: sso-xxxxxx
cookie-refresh-name: sso-yyyyyy
preserve-host: true
scopes:
  - offline_access
match-claims:
  aud: KEYCLOAK_CLIENT_ID
  iss: https://sso.example.com/auth/realms/example
add-claims:
  - name
resources:
  - uri: /prometheus/*
  - uri: /grafana/*
  - uri: /alertmanager/*
```

You'll need to create an OpenID Connect client in Keycloak of type
confidential. I also use refresh tokens (the access tokens expire in
5min) so I added `offline_access` to the "Optional Client Scopes" in the
"Client Scopes" tab.

The `offline_access` is what gives us access to the refresh token which
allows the Gatekeeper to continuously refresh our session. Without it
the access token would expire after 5min and you'd have to reload your
browser tab to get a new one so your requests could be authorized again.
This is fine for API services but incredibly annoying for anyone that keeps
a tab open longer than 5 minutes.

If the Gatekeeper approves the request it sets a number of additional
headers to the downstream. I've disabled the token and the authorization
headers as they're big and none of my backends need access to them. They'll
also get `X-Auth-Roles`, letting your backend know which roles the authenticated
party had in Keycloak (they're extracted from the ID token). You can also get
groups in `X-Auth-Groups` but for that to work you'll have to add a "groups"
mapper in the "Mapper" tab of the client. Set the token claim name to `groups`.

I also added an `add_claims`. Any claim listed there gets added as `X-Auth-$CLAIM`
to the downstream. In this case I now get an `X-Auth-Name` header with the full
name.

You can see the [full list of headers here](https://github.com/keycloak/keycloak-gatekeeper#upstream-headers).

## Reconfiguring the monitor stack

[Previously][prev_post] I showed how I had my monitoring stack behind the Oauth2
Proxy. Now we're going to update it to use the Gatekeeper. You can already see
from the Gatekeeper configuration that it's going to protect `/prometheus/*` for
me, same for Grafana and Alert Manager.

First, the first pass through nginx. It looks a tiny bit different:

```nginx
location /prometheus {
        include /etc/nginx/snippets/rate-limit.conf;
        include /etc/nginx/proxy_params;
        proxy_pass http://127.0.0.1:3001/prometheus;
}
```

The `include .../auth-oauth.conf` is gone now. And instead of proxying to
Prometheus we proxy to the Gatekeeper on `/prometheus`, which is running on port
`3001`.

The Gatekeeper will do the authentication and authorization checks and then
proxy the request on to `upstream-url/prometheus`. So, we're going to need a
second server block in nginx:

```nginx
server {
        listen 127.0.0.1:4181;
        server_name example.com;

        error_log /var/log/nginx/proxy.example.com.error.log warn;
        access_log /var/log/nginx/proxy.example.com.access.log;

        root /var/www/html;
        index index.html;


        location / {
                try_files $uri $uri/ =404;
        }

        location /prometheus {
                include /etc/nginx/oauth_proxy_params;
                proxy_pass http://127.0.0.1:9090/prometheus;
        }
}
```

Here we have a second block which now proxies onwards to the real Prometheus
backend. This server block binds to `127.0.0.1` as there's never any need for
it to be accessible from the outside.

The special `oauth_proxy_params` is a slightly modified version of
`proxy_params` to fix a few headers the Gatekeeper botches:

```nginx
proxy_set_header Host $http_host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto https;
proxy_set_header X-Forwarded-Scheme https;
proxy_set_header X-Scheme https;
proxy_redirect off;
```

The thing here is that we fix the values of `X-Forwarded-Proto`, `-Scheme`
and `X-Scheme` to `https`, as those get lost traversing thorugh the Gatekeeper.
Since we can only ever get here after having been through the regular nginx
(which only handles requests over TLS) this is fine. It also ensures everything
keeps working with cookies as most of my backends set `SecureOnly` on those.

The same set of configuration changes apply for Grafana, Alert Manager or any
other backend you have. It also transparently works with websockets if that's
a concern for you!

## Adding authorization

Now that we have the Gatekeeper we can add authorization. Every entry in the
`resources` can take `roles` and `groups`. `roles` are `AND`ed, so you need to
have **all** the roles to get through, unless you set `require-any-roles: true`.
Groups are `OR`ed, so **any** group of those listed has to match.

```yaml
resources:
  - uri: /prometheus/*
    roles:
      - offline_access
  - uri: /grafana/*
    groups:
      - admin
```

You can combine `roles` and `groups` matches as you want.

## Rate limiting

You'll recall from [my previous post][prev_post] that I had set up rate limiting
based on the existence of the Oauth2 Proxy's cookie. I still do, I just had to
update that check to match the cookie defined in `cookie-access-name`.

One additional thing, if you've employed rate limiting on the `sso.example.com`
host, you'll need to remove that for one endpoint:

```nginx
location ~* ^/auth/realms/([\-_a-z0-9\.]+)/protocol/openid-connect/token {
        include /etc/nginx/proxy_params;
        proxy_pass http://127.0.0.1:8765$request_uri;
}

location / {
        include /etc/nginx/snippets/rate-limit.conf;
        include /etc/nginx/proxy_params;
        proxy_pass http://127.0.0.1:8765;
}
```

If you rate-limit the `/token` endpoint of the realm too aggresively you'll
run into trouble when you need to refresh your token. In my case I was looking
at a Grafana dashboard which had quite a few Prometheus queries going. Once the
5min hit they all attempted to get a new token, hitting `/token`. It was enough
to get me rate limited on that endpoint causing nginx to return 503s making the
Gatekeeper think I was no longer authenticated and re-attempting the full
login flow. That didn't end well. Instead I still rate limit the SSO proxy, just
not the token endpoint. I'll revisit that strategy should it every become an
issue.

## Conclusion

With the Gatekeeper now fronting all your requests you can add authorization
to the mix. This allows you to restrict access to any resource based on a
combination of roles and/or groups of your liking.

Using the `add_claims` you can expose additional information to the backend
you're proxying to. Do ensure that backend only trusts those headers if they're
actually coming from the proxy!

[prev_post]: /2018/10/27/beyondcorp-at-home
