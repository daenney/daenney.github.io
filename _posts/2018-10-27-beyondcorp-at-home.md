---
layout: post
title: "BeyondCorp @ Home"
date: "2018-10-27 17:00:00"
categories: tech
---

BeyondCorp is a different approach to securing access to networked applications
and services.

> Unlike the traditional perimeter security model, BeyondCorp dispels the
> notion of network segmentation as the primary mechanism for protecting sensitive
> resources. Instead, all applications are deployed to the public Internet,
> accessible through a user and device-centric authentication and authorization
> workflow.
>
> -- <cite>https://beyondcorp.com/</cite>

I very much agree with this approach. Using the network as a security boundary,
authentication or even authorization engine is a Bad Idea™️. So I decided to
implement this for the services I run on my home network.

The approach to authorization I have is fairly simple: if you can authenticate
you are authorized. This isn't viable in a large enterprise but for my home
network is perfectly adequate. However, it's relatively simple to expand on
this going forward should I want to limit access to certain applications to
specific groups of people/machines.

## Table of contents

* [Table of contents](#table-of-contents)
* [Components](#components)
    * [Central account management](#central-account-management)
    * [Authentication and authorization service](#authentication-and-authorization-service)
    * [Authentication and authorization proxy](#authentication-and-authorization-proxy)
* [Installing Keycloak](#installing-keycloak)
* [Installing the oauth2 proxy](#installing-the-oauth2-proxy)
* [Configuring nginx](#configuring-nginx)
    * [Proxy Keycloak with TLS](#proxy-keycloak-with-tls)
    * [Require authentication for all resources](#require-authentication-for-all-resources)
* [Rate limiting](#rate-limiting)
* [Protecting the monitoring setup](#protecting-the-monitoring-setup)
    * [Prometheus](#prometheus)
    * [Grafana](#grafana)
* [Logging](#logging)
* [Conclusion](#conclusion)

## Components

In order to achieve a BeyondCorp style solution for my home network I needed
a few different things.

### Central account management

We need to start with having a source of truth for all accounts. This has to
be some kind of central database. Luckily I already have that in the form of
an LDAP server which already powers things like SSH login to all my machines.

You don't have to have an LDAP server, but it can prove useful. If you'd like
to attempt this, you can start with my [Directory Services 101][ds101] series
of posts. [Keycloak][kc] can also function as the identity source of truth.

### Authentication and authorization service

Next, I wanted something that could do the typical authentication and
authorization for systems that don't support LDAP out of the box, mainly SAML
and OpenID Connect/Oauth2. To that end I installed [Keycloak][kc], also known
as RedHat Single Sign-On (RH-SSO). Keycloak uses my LDAP server as the source
of truth for users and groups.

### Authentication and authorization proxy

Unfortunately, quite a few services also don't support either SAML or OpenID
Connect. A number of services don't support any form of authentication and
authorization out of the box and thus have to be placed behind some kind of
proxy that takes care of this.

This is achieved through a combination of [nginx][ngx] and [oauth2_proxy][proxy].

## Installing Keycloak

Keycloak is a rather complex piece of software but has surprisingly accessible
documentation. [Read it][kcdocs], at least the installation and administration
parts, before you get started on this.

Though I consider Keycloak to be a complex piece of software it is easy to run
thanks to the Docker container they provide and the fact it can use an embedded
database. You can also use an external database, like MySQL or Postgres, and it
comes with clustering and high-availability capabilities.

I run Keycloak as a Docker container:

```sh
docker run \
    --name keycloak \
    -h sso.example.com \
    -p 127.0.0.1:8765:8080 \
    -v keycloak_data:/opt/jboss/keycloak/standalone:rw \
    --env-file /etc/docker/config/keycloak/config.env \
    jboss/keycloak:4.5.0.Final
```

The `keycloak_data` is a Docker volume I've created beforehand to persist the
configuration and H2 database. The `config.env` contains the following
values:

```sh
DB_VENDOR=h2
KEYCLOAK_HOSTNAME=sso.example.com
PROXY_ADDRESS_FORWARDING=true
KEYCLOAK_HTTPS_PORT=443
KEYCLOAK_HTTP_PORT=80
KEYCLOAK_USER=admin
KEYCLOAK_PASSWORD=$SECRET_ADMIN_PASSWORD
```

Once you've started this container run through the server configuration
guide and set it up according to your needs. Don't forget to create a separate
realm and if you're using it setup user federation to your LDAP infrastructure.

If you don't use user federation, create a user to test with in your new
realm through Keycloak's UI.

Once you've set that up you'll need to create a OpenID Connect client for
the Oauth2 proxy to use.  All you need is the "Standard Flow" enabled on it
and configure the "Valid Redirects" as `https://example.com/oauth2/callback`.
It should be of "Access Type" confidential.

Expand the "Fine Grained OpenID Connect Configuration" and set all the
"algorithm" fields **except** "User Info Signed Response" to RS256.

Save it and on the "Credentials" tab set "Client Authenticator" to
"Client Id and secret". It'll now present you with a "Secret" that you'll
need to provide the Oauth2 proxy with, together with the "Client ID" from
the "Settings" tab.

## Installing the oauth2 proxy

You probably guessed this one already, I'm running it with Docker!

```sh
docker run \
    --name oauth2_proxy \
    -p 127.0.0.1:4180:4180 \
    --expose 4180 \
    -v /etc/docker/config/oauth2_proxy/config.cfg:/etc/oauth2_proxy.cfg:ro \
    bitnami/oauth2-proxy:0.20180625.74543-debian-9 \
    -http-address=0.0.0.0:4180 -config=/etc/oauth2_proxy.cfg
```

The `oauth2_proxy.cfg` looks like this:

```ini
provider = "oidc"
oidc_issuer_url = "https://sso.example.com/auth/realms/example.com"
redirect_url = "https://example.com/oauth2/callback"
upstreams = [
     "http://172.17.0.1:4181/",
]
pass_basic_auth = true
pass_user_headers = true
pass_host_header = true
email_domains = [
    "*",
]
client_id = "KEYCLOAD_CLIENT_ID"
client_secret = "KEYCLOAK_CLIENT_SECRET"
pass_access_token = false
cookie_name = "_oauth2_proxy"
cookie_secret = "SOME_RANDOM_STRING"
cookie_domain = "example.com"
cookie_expire = "168h"
cookie_refresh = 0
cookie_secure = true
cookie_httponly = true
set_xauthrequest = true
```

I'm not going into detail here as to what every option does, you can read that
in the [proxy][proxy]'s own documentation.

## Configuring nginx

We need to do 2 things, proxy all requests on `sso.example.com` to the
Keycloak server and protect all resources on `example.com/*`. You can also
put things on subdomains, like `app.example.com` if you prefer.

### Proxy Keycloak with TLS

Here's the nginx config:

```nginx
server {
        listen 80;
        listen [::]:80;
        server_name sso.example.com;

        error_log /var/log/nginx/sso.example.com.error.log warn;
        access_log /var/log/nginx/sso.example.com.access.log;

        location / {
                return 301 https://$host$request_uri;
        }
}

server {
        listen 443 ssl http2;
        listen [::]:443 ssl http2;
        server_name sso.example.com;

        error_log /var/log/nginx/sso.example.com.error.log warn;
        access_log /var/log/nginx/sso.example.com.access.log;

        include /etc/nginx/snippets/ssl.conf;
        include /etc/nginx/snippets/secure-headers.conf;

        location / {
                include /etc/nginx/snippets/rate-limit.conf;
                include /etc/nginx/proxy_params;
                proxy_pass http://127.0.0.1:8765;
        }
}
```

The `snippets/ssl.conf` contain a number of `ssl_*` directives to
secure the connections to this server with TLS. `snippets/rate-limit.conf`
applies some configuration for rate limiting (which I'll show you later)
and `snippets/secure-headers.conf` include some `add_header` directives
like Strict Transport Security.

`proxy_params` contains a few headers to set when proxying requests with
the `proxy_pass` directive. These are fairly important, here's the ones
I use:

```nginx
proxy_set_header Host $http_host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Scheme $scheme;
proxy_set_header X-Scheme $scheme;
proxy_redirect off;
```

With that in place you should now be able to go to `sso.example.com` and be
presented with the Keycloak UI.

### Require authentication for all resources

Now we're going to leverage nginx's [auth_request][ngxauthreq] module to protect
all the resources exposed by this server paired with the Oauth2 Proxy.

The way this works is like this:

* For every request, hit `/oauth2/auth`
* If that endpoind responds with success, let the request through
    * Set some additional headers so that other applications can use that
* If not, the user is either unauthenticated or the authentication has expired
  so send them on to `/oauth2/signin` instead

This can be configured like so in nginx:

```nginx
server {
        listen 443 ssl http2;
        listen [::]:443 ssl http2;
        server_name example.com;

        error_log /var/log/nginx/example.com.error.log warn;
        access_log /var/log/nginx/example.com.access.log;

        include /etc/nginx/snippets/ssl.conf;
        include /etc/nginx/snippets/secure-headers.conf;

        root /var/www/html;
        index index.html;

        location /oauth2/ {
                proxy_pass       http://127.0.0.1:4180;
                include /etc/nginx/proxy_params;
                proxy_set_header X-Auth-Request-Redirect $request_uri;
        }

        location = /oauth2/auth {
                proxy_pass       http://127.0.0.1:4180;
                include /etc/nginx/proxy_params;
                proxy_set_header Content-Length   "";
                proxy_pass_request_body           off;
        }

        location / {
                try_files $uri $uri/ =404;
        }

        location /secret {
                include /etc/nginx/snippets/rate-limit.conf;
                include /etc/nginx/snippets/auth-oauth2.conf;
                include /etc/nginx/proxy_params;
                proxy_pass http://some.backend.you.want.to.keep/secret;
        }
}
```

So what's going to happen? The first time you try to go to `example.com/secret`
you'll be unauthenticated. As such you won't have a valid cookie set by the
Oauth2 Proxy meaning the call to `/auth2/auth` will fail. Since that happens
you'll now be sent on to `/oauth2/signin` which will present you with a screen
like this one.

![login screen](https://cloud.githubusercontent.com/assets/45028/4970624/7feb7dd8-6886-11e4-93e0-c9904af44ea8.png)

Once you click the blue login button you'll be redirected to Keycloak where
you can login with your credentials and you'll be asked to grant the Oauth2
Proxy access to certain scopes. Assuming that all passed correctly Keycloak
will redirect you back to the Oauth2 proxy's `/oauth2/callback` URL telling
the proxy the authentication was succesfull. In turn it will set a few
headers in the response (which we extract and set on any response we proxy
using `auth_request_set`) and you'll also be given a cookie.

The next time you go to that same endpoint your browser will send the cookie
it got along with the request. That cookie will end up getting submitted to
`/oauth2/auth` and if it's still valid the Oauth2 proxy will return a success,
populate the headers and nginx will then proxy you on to your backend!

Now you're probably wondering what's in that `snippets/auth-oauth2.conf`, here
it is:

```nginx
auth_request /oauth2/auth;
error_page 401 = /oauth2/sign_in;

auth_request_set $user          $upstream_http_x_auth_request_user;
auth_request_set $email         $upstream_http_x_auth_request_email;
auth_request_set $auth_cookie   $upstream_http_set_cookie;
proxy_set_header X-User  $user;
proxy_set_header X-Email $email;

add_header Set-Cookie $auth_cookie;
```

This instructs nginx that for this `location` block it has to get a succes
response from the `/oauth2/auth` endpoint.

This doesn't just work for resources that you `proxy_pass`, it works for
any kind of location block, even if it's just static files.

## Rate limiting

As you've seen in my nginx examples I have a `snippets/rate-limit.conf` that
gets included in a lot of places. This implements rate limiting for all
endpoints, in order to ensure that neither internal nor external users or
services can bombard my server with enough requests to exhaust its resources.

The `snippets/rate-limit.conf` itself is rather unremarkable and looks
like this:

```nginx
limit_req zone=req_zone burst=5 nodelay;
limit_req zone=req_zone_wl burst=200 nodelay;
```

This just makes it use two different zones to limit the request rate, while
allowing for a bit of burst.

The zones are configured in nginx.conf's `http` block and look like this:

```nginx
map $http_cookie $limit_key {
    default $binary_remote_addr;
    "~*_oauth2_proxy=.+" "";
}

limit_req_zone $limit_key zone=req_zone:10m rate=5r/s;
limit_req_zone $binary_remote_addr zone=req_zone_wl:10m rate=500r/s;
```

This is where it gets interesting. The end result of this is that
unauthenticated users will be rate limited to 5 requests per scond, whereas
authenticated users are given 500 requests per second.

The reason this works is thanks to the `map` directive right above it. That
one defines a new variable `$limit_key` which will be assigned a value based
on what's in `$http_cookie`.

If `$http_cookie` contains the cookie from the Oauth2 proxy (i.e the user is
or at the very least was authenticated), we assign `$limit_key` the empty string.
Else, when the user is not authenticated, we assign it the value of `$binary_remote_addr`
instead.

The trick now is in how `$limit_key` is used by `limit_req_zone`. If the
first argument to `limit_req_zone` is the empty string, the `limit_req_zone`
directive does not apply. This means that in the case of an authenticated user
they'll fall through to the next `limit_req_zone` directive with the much larger
request allowance.

Any unauthenticated user will have a `$limit_key` with the value of `$binary_remote_addr`
which is always populated, and thus be assigned to the first zone.

It's worth noting here that all it takes to defeat this rate limiting is to add a
cookie named `_oauth2_proxy` to any request you do. But that's already quite a
bit more than what any bot does (and it'll fail the authentication stup after
that anyway) which makes this good enough for now.

You can change the name of the cookie the Oauth2 Proxy will look for and use
something more obscure, like a randomly generated string. That would at least
make it a bit more annoying for anyone trying to defeat this meassure as they'll
have to manage to either MITM you or successfully authenticate once to figure
out what the cookie name is they need to fake.

## Protecting the monitoring setup

I run a standard Prometheus + Grafana monitoring setup at home that I want
to be able to access from anywhere. This means both Prometheus and Grafana
need to be put behind the Oauth2 proxy.

### Prometheus

Prometheus has no concept of users or access levels so that one is pretty
simple, just put it behind the proxy:

```nginx
location /prometheus {
    include /etc/nginx/snippets/rate-limit.conf;
    include /etc/nginx/snippets/auth-oauth2.conf;
    include /etc/nginx/proxy_params;
    proxy_pass http://127.0.0.1:9090/prometheus;
}
```

You'll need to run Prometheus with `--web.external-url=https://example.com/prometheus`
for this to work, but other than that you're golden!

### Grafana

Grafana does have a concept of users, organisations and different access
levels. It supports Oauth2 by itself but that would mean configuring yet
another client in Keycloak and not being able to benefit from the SSO
like features that I would get from having it behind the Oauth2 proxy.

So instead I've configured Grafana with [`auth.proxy`][gfauth] instead.
Here's the relevant bits from `grafana.ini`:

```ini
[server]
domain = example.com
root_url = https://example.com/grafana
enforce_domain = true

[session]
cookie_secure = true

[users]
allow_sign_up = false
auto_assign_org = true

[auth]
disable_login_form = true
disable_signout_menu = true

[auth.anonymous]
enabled = false

[auth.basic]
enabled = false

[auth.proxy]
enabled = true
header_name = X-User
header_property = username
auto_sign_up = true
headers = Email:X-Email
```

On the nginx side, this is the location block:

```nginx
location /grafana/ {
    include /etc/nginx/snippets/rate-limit.conf;
    include /etc/nginx/snippets/auth-oauth2.conf;
    include /etc/nginx/proxy_params;
    proxy_pass http://127.0.0.1:3000/;
}
```

When a request gets proxied to Grafana the `auth-oauth2.conf` ensures that
two headers are set: `X-User` with the username and `X-Email` with the
email address. The `auth.proxy` configuration maps those headers to user
account fields in Grafana and because of `auto_sign_up = true` accounts that
don't yet exist will automatically get created the first time a user
browses to Grafana!

**NOTE**: Grafana will blindly trust those headers, allowing anyone to
fake them if Grafana can be accessed without having the request proxied
by nginx. This is why I run Grafana bound to `127.0.0.1` instead and
don't have port `3000` open, ensuring you can only get to it through
nginx.

Now that Grafana is protected we can change the Prometheus datasource to
use an "Access Type" of "Browser" and set the URL to Prometheus' public
endpoint, `https://example.com/prometheus`. With that the browser will be
doing the requests to Prometheus instead of Grafana, passing your cookie
along with the request.

## Logging

It can be helpful to have nginx log the user that's doing the request.
Unfortunately, nginx will only log `$remote_user` in its default log
format which is only set when using HTTP Basic Authentication. If you
try to be clever and add a `auth_request_set $remote_user $upstream_http_x_auth_request_user;`
to `snippets/auth-oauth2.conf` you'll end up with a very angry nginx
as it won't allow you to redefine that variable.

Instead I had to create my own log format and update all the `access_log`
directives to use my custom format. I defined one named `all` like this:

```nginx
log_format all '$remote_addr - $user [$time_iso8601] '
            '"$request" $status $body_bytes_sent '
            '"$http_referer" "$http_user_agent" "$gzip_ratio" '
            'rt="$request_time" uct="$upstream_connect_time" uht="$upstream_header_time" urt="$upstream_response_time"';
```

You can add a lot more to it and you could also consider using JSON instead
if you want to ship it off to something like an ELK stack:

```nginx
log_format all escape=json
    '{'
    '"time_local":"$time_local",'
    '"remote_addr":"$remote_addr",'
    '"remote_user":"$user",'
    '"request":"$request",'
    '"status": "$status",'
    '"body_bytes_sent":"$body_bytes_sent",'
    '"request_time":"$request_time",'
    '"http_referrer":"$http_referer",'
    '"http_user_agent":"$http_user_agent"'
  '}';
```

The full documentation on how to configure logging and logging formats
is part the [`ngx_http_log_module` documentation][ngxlog].

## Conclusion

That's about it. With relatively little effort (aside from configuring
Keycloak) you can spin up a "BeyondCorp Lite" setup that should be
sufficient for a home or lab setup, or a small startup.

In a follow-up on this post I'll show you how to swap out Oauth2 Proxy
for [Keycloak Gatekeeper][kgate] instead. It is similar in spirit, but contrary
to Oauth2 Proxy you can define additional requirements per endpoint.

This would allow me to complete the final piece of the puzzle,
where aside from authentication I can now also have authorization
requirements by leveraging Keycloak roles.

Because Keycloak acts as both a SAML and OpenID Connect service you can
configure many third-party services to use your Keycloak instance for
authentication. You can use SAML together with myriads of other services
and use OpenID Connect/Oauth2 to protect your own applications and APIs
with. Do note that for third-party SAML support you usually need to pay
for the "enterprise" package of that service, which can carry a rather
spicy price tag.

[ds101]: https://daenney.github.io/2017/07/02/ldap-101
[kc]: https://www.keycloak.org/
[kcdocs]: https://www.keycloak.org/docs/
[kgate]: https://github.com/keycloak/keycloak-gatekeeper
[ngx]: https://nginx.org/
[proxy]: https://github.com/bitly/oauth2_proxy
[ngxauthreq]: https://nginx.org/en/docs/http/ngx_http_auth_request_module.html
[ngxlog]: https://nginx.org/en/docs/http/ngx_http_log_module.html
[gfauth]: http://docs.grafana.org/auth/auth-proxy/
