---
layout: post
title:  "GeoIP based filtering with iptables"
categories: security iptables geoip
---

One of the issues I run into when running a server, at home or anywhere else,
is the crazy amount of random attempts at SSH logins. My [SSH configuration
is strict enough][1] that most of these attempts just die on the key exchange,
they never even get past the handshake. Then there's fail2ban ensuring you
get temporarily blocked if you're obviously trying to brute force anything.

Looking at the `auth.log` a lot of these attempts stem from Russia, China,
various other parts of Asia, Africa and South America. The US is guilty of
it too. I'd much rather block these attempts before we even get to an SSH
handshake, HTTP or anything else.

It turns out there's a GeoIP module for iptables that you can use to do just
that. Except in very rare situations my friends and I are somewhere in the
EU or the US. So it's perfectly reasonable to drop any connection that doesn't
come from there as there's no legitimate reason for those to arrive on most of
my machines.

## Installation

On Debian you'll need `xtables-addons-common` and `xtables-addons-dkms` (yes
a kernel module, exciting!) as well as `libtext-csv-xs-perl` installed. Once
you've downloaded and extracted the rules you can then start blocking based
on country code.

Throw the following in `/etc/cron.weekly`, make it executable and owned by
`root`. This will ensure we fetch and update the GeoIP database on a weekly
basis. Also, run it once by hand before you add any rules:

```bash
#!/bin/bash
set -euo pipefail

set +e
if ! dpkg -l xtables-addons-common >/dev/null ; then
        apt install xtables-addons-common
fi
if ! dpkg -l libtext-csv-xs-perl >/dev/null ; then
        apt install libtext-csv-xs-perl
fi
set -e

if [ ! -d /usr/share/xt_geoip ]; then
        mkdir /usr/share/xt_geoip
fi

geotmpdir=$(mktemp -d)
csv_files="${geotmpdir}/GeoIPCountryWhois.csv ${geotmpdir}/GeoIPv6.csv"
OLDPWD="${PWD}"
cd "${geotmpdir}"
/usr/lib/xtables-addons/xt_geoip_dl
/usr/lib/xtables-addons/xt_geoip_build -D /usr/share/xt_geoip ${csv_files}
cd "${OLDPWD}"
rm -r "${geotmpdir}"
exit 0
```

## Configuration

The `iptables` rules themselves are very simple:

```
iptables -A INPUT -m geoip ! --src-cc CO,UN,TR,YC,OD,ES -i <outside interface> -m conntrack --ctstate NEW -j DROP
ip6tables -A INPUT -m geoip ! --src-cc CO,UN,TR,YC,OD,ES -i <outside interface> -m conntrack --ctstate NEW -j DROP
```

So I'm using `conntrack` and a `cstate` of `NEW` here since I want to drop
incoming connections from those countries but I don't want to drop incoming
traffic for connections to anywhere for connections that this machine
established itself. If you want to do that I would rather suggest you
explicitly whitelist the things you want to allow connections to. You can get
pretty clever by translating ASNs into ipsets and filtering on those for
example.

My firewall at home is managed by firehol instead so I insert these rules on
the interface configured for internet access and I do the same for my IPv6
tunnel:

```
ipv4 interface enp7s0f1 internet
        policy drop
        protection strong
        iptables -A in_internet -m geoip ! --src-cc CO,UN,TR,YC,OD,ES -m conntrack --ctstate NEW -j DROP
        server "ping" accept
        client all accept

ipv6 interface ipv6rd internet6
        policy drop
        protection strong
        ip6tables -A in_internet6 -m geoip ! --src-cc CO,UN,TR,YC,OD,ES -m conntrack --ctstate NEW -j DROP
        server "ping" accept
        client all accept
```

Due to the placement of the rule it won't even allow ping's from those country
codes. Note that these rules don't contain an explicit
`-i <outside interface>` match as the `in_internet*` chains only match
incoming traffic from the outside world.

## Caveats

Keep in mind that this does GeoIP based blocking but people in countries you
haven't thought of might have a perfectly legitimate reason to want to
communicate with your machine. If you're running email services on a host
employing GeoIP based blocking is probably a bad idea.

Also, this relies on a GeoIP database. So an error in that database can result
in something not getting blocked or inadvertently getting blocked.

Though doing GeoIP based blocking can be handy it's no substitute for having a
good firewall in place and properly protecing any other services you have
running on a machine.

[1]: https://wiki.mozilla.org/Security/Guidelines/OpenSSH#Modern_.28OpenSSH_6.7.2B.29
