---
layout: post
title:  "My home monitoring setup"
categories: monitoring prometheus docker
---

Over the past few months I've started to reassemble a home server. I managed
to get a great server board with 2 Xeon E5's and 128GB of ECC RAM (b/c why
not?) and spent Saturday breaking in the hard drives, setting everything up
to be nice and encrypted and so on.

One of the things I like to have at home is a decent monitoring system. I've
toyed with Prometheus before but never really used it. I like its design and
the PromQL language so I figured I'd set it up. It never hurts to be
familiar with it since it's likely I'll encounter it in the wild at some
point.

However, when you have a nice and pristine server you kinda don't want to end
up throwing binaries and cnfiguration all over it. So I figured I would try
this with containers this time around. Though Docker is not super awesome just
yet at actually containing stuff they provide the filesystem level isolation
I wanted. Since I needed multiple containers I figured Compose sounds like a
good way to do this. Besides, using one new system to set up a bunch of other
new ones, how hard could it be?

Ended up spending most of the day on it but managed to get it to all play
together. It took some digging, especially because Compose does some things
for you a simple `docker run` doesn't. Because of that you can easily get
very confused when reading the documentation assuming that one concept would
apply to the other.

Now that I have it all figured out though I have a setup I very much like.
Safe for needing to backup the Prometheus data I can spin this stack up
anywhere else too just as quickly and get going, which is really nice.

If you want to take a look, you can find the config and the
`docker-compose.yml` file right here: https://github.com/daenney/monitoring.
And yes, I still use Puppet to manage that.

One great thing I ran into... my stupid home router doesn't do SNMP very
well. Once it gets busy with more network traffic it doesn't only stop
responding to SNMP queries at all, it doesn't even update its packet counters
etc. So I guess the next project is going to be replacing my router :).
