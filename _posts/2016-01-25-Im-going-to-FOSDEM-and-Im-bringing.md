---
layout: post
title:  "I'm going to FOSDEM and I'm bringing"
categories: foss fosdem security streisand vpn openvpn ipsec socks socks5
---

FOSDEM is a wonderful event. But as with any event with geeks people
will try to sniff your traffic, mess with GSM, grab your credentials and
what not.

The best way to stay safe? Don't bring electronics with you or have them
in flight mode (laptop included). No Bluetooth, no WiFi, no
GSM/3G/tethering, nothing.

If that doesn't sound all that practical there's a few things you can
do.

1. Spin up a [Streisand](https://github.com/jlund/streisand) server so you
   can VPN all the things. It comes equipped with:
    1. L2TP/IPSec VPN
    2. OpenVPN on regular port and 443
    3. OpenVPN wrapped in TLS/SSL over port 993 (through stunnel, using the imaps
     port, great to avoid deep-packet inspection)
    4. Shadowsocks (SOCKS5, encrypted, with an easy GUI)
    5. SSH (SOCKS5 proxy) on port 22 and 443
    6. Tor bridge with Obfsproxy
    7. dnsmasq (to do all your DNS queries for you)
    8. SSH only through a bastion you've connected to before and have verified
     its fingerprint. Do not disable `StrictHostKeyChecking` for that host.
2. Shut off any wireless you don't really really abso-total-utely need (Bluetooth comes
to mind).

Streisand is nice enough to also spin up an nginx accessible over
TLS/SSL only with all the necessary instructions and a mirror of the
binaries so you can fetch them directly from your own machine. It also
configures your machine so that just about nothing is logged.

The L2TP/IPSec VPN is very useful for mobile devices. Just about any
smartphone supports it as a VPN option allowing you to throw all traffic
over it. OpenVPN is also a good option for Android and iOS.

SOCKS5 proxies are great if you only want to hide/proxy/unblock certain
traffic. Shadowsocks has the added option of being able to work as a
transparent proxy so you don't have to configure every application
individually to use it.

As a last note, since it's possible to securely communicate over WiFi +
one of the VPN solutions, you can disable cellular capabilities on your
phone entirely or at least the data portion of it (if you don't want to
accumulate a huge roaming bill).

Last but not least, no matter how secure you think you are, limit your
usage. Do your Twitter and Facebook if you want to or check your email
once VPN is up, SSH to your bastion and grab your IRC session, but avoid
doing things with online banking, government services etc.
