---
layout: post
title: "BeyondCorp @ Home: Authentication and authorization proxy with OpenResty"
categories: tech
---

In [a previous post][prev_post] I showed you how to set up Gatekeeper as a proxy
to enfroce authorization on requests. The problem with Gatekeeper is that it
required a lot of additional configuration, an additional proxy hop and is a
separate component.

What this post will do instead is use the [OpenResty build of nginx with the
OIDC plugin](https://github.com/zmartzone/lua-resty-openidc) to avoid all of
that. This brings the complexity back down to just running nginx with it acting
as a Relaying Party to do authenticaiton and provide authorization information
to backends.

## Table of contents

* [Table of contents](#table-of-contents)
* [Design changes](#design-changes)
* [Installing OpenResty and the OIDC plugin](#installing-openresty-and-the-oidc-plugin)
* [Proxying to a backend](#proxying-to-a-backend)
  * [Authorization](#authorization)
* [Conclusion](#conclusion)

## Design changes

Since we no longer need the Gatekeeper we end up with a request flow like this:

```text
+-----------------------+               +----------------------+
|                       |               |                      |
|       nginx:443       | <-----------> |     OIDC Provider    |
|                       |               |                      |
+----------+------------+               +----------------------+
           |
           |
           v
+-----------------------+
|                       |
|     backend:port      |
|                       |
+-----------------------+
```

What will happen now is:
* User request comes in, is redirected to the OIDC provider to login
* ID and access token are stored in a session in nginx memory and we set a cookie for the user
  * The cookie has the `httpOnly` and `secure` attributes set on it
  * You can use memcached or redis, but shared memory is fine for a home setup
  * You can configure the server to try and silently renew the token if it's expired
* Using the session ID in the cookie the server looks up the session, checks token validity and
  then extracts data from the token and sets those as HTTP Request headers to the backend

## Installing OpenResty and the OIDC plugin

OpenResty is a distribution of Nginx paired with LuaJIT and a bunch of third-party
modules. Cetrain distributions have OpenResty packages and OpenResty provide
[official packages themselves](https://openresty.org/en/linux-packages.html).

Once you've got it installed and copied your nginx configuration over, you'll
need to install a few Lua modules:

```sh
# opm install zmartzone/lua-resty-openidc ledgetech/lua-resty-http bungle/lua-resty-session cdbattags/lua-resty-jwt
```

## Configuring OIDC in OpenResty

You'll need a configuration like the following. I've saved this in
`snippets/auth.conf` so I can include it wherever I need it.

```nginx,lua
set $session_cipher none;                 # don't need to encrypt the session content, it's an opaque identifier
set $session_storage shm;                 # use shared memory
set $session_cookie_persistent on;        # persist cookie between browser sessions
set $session_cookie_renew      3600;      # new cookie every hour
set $session_cookie_lifetime   86400;     # lifetime for persistent cookies
set $session_name              sess_auth; # name of the cookie to store the session identifier in

set $session_shm_store         sessions;  # name of the dict to store sessions in
# See https://github.com/bungle/lua-resty-session#shared-dictionary-storage-adapter for the following options
set $session_shm_uselocking    off;
set $session_shm_lock_exptime  3;
set $session_shm_lock_timeout  2;
set $session_shm_lock_step     0.001;
set $session_shm_lock_ratio    1;
set $session_shm_lock_max_step 0.5;

access_by_lua '
  local opts = {
    discovery = "https://<KEYCLOAK>/auth/realms/<REALM>/.well-known/openid-configuration",
    -- Create an application with your OIDC provider and use the returned client ID and secret here
    client_id = "CLIENT_ID",
    client_secret = "CLIENT_SECRET",
    redirect_uri = "https://<DOMAIN>/auth",
    logout_path = "/logout",
    -- Scopes to request; group contains group memberships, offline_access gives us a refresh token
    scope = "openid email profile group offline_access",
    redirect_after_logout_uri = "https://<KEYCLOAK>/auth/realms/<REALM>/protocol/openid-connect/logout?redirect_uri=https%3A%2F%2F<DOMAIN>",
    redirect_after_logout_with_id_token_hint = false,
    renew_access_token_on_expiry = true,
    access_token_expires_leeway = 60,
    -- Storing the access token also includes the refresh token letting the server transparently
    -- renew the session
    session_contents = {id_token=true, access_token=true}
  }

  -- Only redirect to auth page if client requests text/html, reject with 403 otherwise
  local action = "deny"
  if ngx.var.http_accept then
    for ct in (ngx.var.http_accept .. ","):gmatch("([^,]*),") do
      if string.sub(ct, 0, 9) == "text/html" then
        action = null
        break
      end
    end
  end

  -- call authenticate for OpenID Connect user authentication
  local res, err = require("resty.openidc").authenticate(opts, null, action)
  if err then
    ngx.status = 403
    ngx.say(err)
    ngx.exit(ngx.HTTP_FORBIDDEN)
  end

  -- set data from the ID token as HTTP Request headers
  ngx.req.set_header("X-Auth-Audience", res.id_token.aud)
  ngx.req.set_header("X-Auth-Email", res.id_token.email)
  ngx.req.set_header("X-Auth-ExpiresIn", res.id_token.exp)
  ngx.req.set_header("X-Auth-Groups", res.id_token.groups)
  ngx.req.set_header("X-Auth-Name", res.id_token.name)
  ngx.req.set_header("X-Auth-Subject", res.id_token.sub)
  ngx.req.set_header("X-Auth-Userid", res.id_token.preferred_username)
  ngx.req.set_header("X-Auth-Username", res.id_token.preferred_username)
  ngx.req.set_header("X-Auth-Locale", res.id_token.locale)
';
```

You also need to allocate the `sessions` dictionary in which the server will
store the sessions:

```nginx
http {
   lua_shared_dict sessions 10m;
}
```

## Proxying to a backend

Proxying to a backend is now a question of including the `auth.conf` snippet
and the right `proxy_pass` directive:

```nginx
server {
	listen 443 ssl http2;
	listen [::]:443 ssl http2;
	server_name <DOMAIN>;

  location / {
		try_files $uri $uri/ =404;
	}

	location = /auth {
		include snippets/auth.conf;
	}
	location = /logout {
		include snippets/auth.conf;
	}

	location /prometheus {
		include snippets/auth.conf;
		include snippets/oauth_proxy_params.conf;
		proxy_pass http://127.0.0.1:9090/prometheus;
	}
}
```

The contents of `snippets/oauth_proxy_params.conf` should look something
like this:

```nginx
proxy_set_header Host $http_host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Scheme $scheme;
proxy_set_header X-Scheme $scheme;
proxy_redirect off;
```

### Authorization

Though we can directly proxy the request to the backend, we could also
choose to do additional checks now that we have all these headers with
interesting data.

To that end, you can combine `access_by_lua_block` with
`ngx.req.get_headers()` after the `include snippets/auth.conf` and
before the `proxy_pass` to check things like the content of `X-Auth-Groups`.

## Conclusion

We now have an OpenResty proxy configured as an OIDC Relaying Party. It will
direct the user to authenticate and create a session for the user so they
can access applications protected by our proxy. The cookie is domain wide,
effectively creating a Single Sign On experience.

Our proxy will validate the user session and set a number of identifying
attributes as HTTP Request headers to its backends. This allows the application
we're proxying to to know who the user is and what groups they're a member
of. Group membership is typically used for authorization purposes.

It's also possible to configure most OIDC providers to add custom claims to
the ID token if you need to expose attributes specific to your environment.
You'll have to add those to the `scope` list the proxy is requesting and add
an equivalent `ngx.req.set_header`.

[prev_post]: /2018/10/30/beyondcorp-at-home-authz
