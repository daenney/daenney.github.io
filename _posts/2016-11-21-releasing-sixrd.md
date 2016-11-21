---
layout: post
title:  "Releasing sixrd"
categories: ipv6 6rd network
---

My ISP (Telia) doesn't do native IPv6 yet (like most ISPs unfortunately).
However, they do support something called IPv6 Rapid Deployment, also known
as [6rd][6rd]. What it does is fairly simply, it encodes in the information
you get from your ISP during a DHCPv4 chat the information needed to set
up a [6to4][624] tunnel with an endpoint provided by your ISP. Getting native
v6 would be the best but this is probably the closest I'm going to get in a
while.

## Tunnels tunnels tunnels

Now sure, you can get a 6to4 tunnel with any tunnel broker but having an
endpoint provided by your ISP means this tunnel operates entirely within their
network. This rather dramatically reduces latency/RTT amongst other things. In
my case running a `ping` vs a `ping6` to `google.com` over the tunnel Telia
provides I take a 1ms hit. Which is pretty awesome.

Unfortunately, one of the nasty things with doing DHCP and having a dynamic
address handed out to you is that when it changes, your tunnel dies. But with
this 6rd thing you get all the information you need to reconfigure that tunnel
as part of the DHCP exchange.

## State of 6rd

A number of home routers support this, including ASUS and anything built on
Open/DD-WRT (from what I've been able to gleam). However, I have switched to
using a Linux box as my home router and there's basically no support for 6rd
anywhere.

There are some resources on the internet and some dubious and only sometimes
functioning scripts to help you, none of them have worked particularly well
for me. There is also a huge lack of proper documentation on the topic and
generally a lot of confusion to go around. It took a fair amount of time to
scrape this all together until I had a working system.

This seems to be an unfortunate trend when it comes to IPv6. The documentation
isn't very helpful, the specs are... never mind those, lots of docs contradict
each other, weird vendor-specific hacks and implementation "features" all over
the place. IPv6 is most certainly the future but considering the current state
of the art and a generally lacking positive business case for ISPs to deploy
it in the first place a lot of us will be waiting for a long time.

## Hello world, meet sixrd

So today, I'm hoping to fix that once and for all. I spent some time coding a
little helper called [sixrd][sixrd] which when given the appropriate
information can configure and reconfigure this 6to4 tunnel for you. In order
to do this entirely automagically it ships with a dhclient-script hook that
gets triggered whenever the system has a DHCP exchange with your ISP.

The installation and usage instructions are all in the [sixrd README][sixrd]
and I'm working on properly versioning this and packaging it up. Please try
it out and let me know if it works for you or not!

**P.S** The `configuration` directory contains an example configuration for
setting up [FireHOL][firehol], an iptables firewall manager, for you. It took
me another few hours to get this right and have packets flowing in both
directions so if you happen to be using FireHOL, take a look. If not, please
feel free to contribute configuration for other firewall managers, raw
iptables but also radvd and anything else you might use to power your new
dual-stack home network. Woo!

[6rd]: https://en.wikipedia.org/wiki/IPv6_rapid_deployment
[624]: https://en.wikipedia.org/wiki/6to4
[sixrd]: https://github.com/daenney/sixrd
[firehol]: https://firehol.org
