---
layout: post
title: "Monitoring my WiFi access point with Prometheus"
categories: monitoring golang prometheus
---

My home WiFi router is an ASUS RT-AC66U. It's a great device with a tolerable
manufacturer provided UI and quite a lot of advanced features. Though it's
marketed as a WiFi router I use it as a WiFi access point and switch, it
doesn't route. I have a Linux box that does that.

Since a lot of my devices are wireless a lot of my traffic flows through my
WiFi access point. I wanted to be able to monitor that and graph things like
how much traffic I'm doing over 2.4GHz vs. 5GHz etc.

## At first there was SNMP

The device supports SNMP out of the box. And there's an SNMP exporter for
Prometheus. Match made in heaven! I set it up and sure enough I started to
get data in and I quickly had a pretty dashboard up showing traffic going
through the switch (so just wired) and what traffic was coming through 2.4GHz
vs. 5GHz.

All was well until I ran a speedtest to see how that would manifest in the
graphs. And manifest it did, albeit in a very unexpected way. The graphs
flatlined. Completely dead. It seems that when it got busy handling lots of
packets it stopped updating the SNMP counters for whatever reason. Once it
caught up the counters would increment but not before. The scrapes didn't
appear to be failing so I'm fairly certain it's an issue with how SNMP and
the device were interacting.

## Prometheus exporter

At that point I figured someone else might've written a Prometheus exporter
that I could just run on my device. Since it runs the ASUSWRT-Merlin firmware
and I have Entware at my disposal I can pretty much run anything on it.

Sure enough, someone wrote an [OpenWRT exporter][owrtexp]. I installed Lua,
copied the code over and ran it. Unfortunately not everything worked out of
the box so I found myself battling the Lua code in order to fix it. Lua is
fairly easy to read but the string pattern matching kept tripping me up (the
exporter was running commands and scraping the output). Though I managed to
fix it after a few hours the rage it induced was enough that I decided I was
just going to write some Go code myself instead.

## MIPS and Go

Quick side bar here. A lot of home routers run on MIPS units with a Linux based
operating system. It's only since Go 1.8 that you can cross-compile to target a
(linux) 32-bit MIPS device, Big or Little Endian.

However, for Go to be able to run it additionally requires the kernel to have
access to a Floating Point Unit or for the kernel to provide FPU emulation.
Most home routers don't come with an FPU but most of the custom firmware at
least have the kernel emulation enabled.

Once you've figured out if you can run Go code you can compile it with
`GOARCH=mipsle` and `GOOS=linux`. Change it from `mipsle` to `mips` if your target
is Big Endian.

## Prometheus Node Exporter

Shortly after `go get`ing the Prometheus client library it occured ot me that
I should just be able to run the node exporter the Prometheus project has
built. All I had to do was cross-compile it.

Though I hit a snag there too it was a very minor one that was [quickly fixed
by adding the appropriate build tags][build-mips] to one of the source files.
Totally happy I `scp`'ed the resulting `node_exporter` binary over to my router
and ran it. Everything seemed to start up fine until:

```
FATA[0000] listen tcp :9100: errno -9   source="node_exporter.go:189"
```

Well. That's not good. Error 9 here is "bad file descriptor". Essentially what
is going on is that the `net.Listen()` call that `http.ListenAndServe` does
was failing to bind to the port.

The typical reason for this is that the port is already in use, but Go actually
tells you when that's the case. Whichever port I picked, verified free and what
not, all I got is that error.

Searching a bit through the docs I found a tidbit on the [Go wiki that says at
least Linux kernel 2.6.23][linux-26] is required. Logging in to my router I ran
a `uname -a` and sure enough: `Linux router 2.6.22.19 #1 Wed Mar 29 00:41:07 EDT 2017 mips ASUSWRT-Merlin`.

Damn. But that can't be it, right? Nothing changed between 2.6.22 and 2.6.23
that could affect something as basic setting up a socket and binding to a
port? At that point I should've just ran `strace` which would later on reveal
why it was breaking but for whatever reason that didn't occur to me. So what
does one then do? Well... you use QEMU to emulate a 32-bit MIPS Little Endian
unit and you install Debian stable on it! That comes with kernel 3.16 on which
we'll surely be able to reproduce this bug and file a report with the Go
project.

### QEMU

Getting this to run on QEMU was painful. Between the outdated tutorials,
QEMU's help being quite overwhelming and rather unhelpful error messages it
took an hour or so just to get everything to boot right.

For posterity:

* Download the `initrd.gz` and `vmdlinux` from the
  [`installer-mipsel`][di-mipsel] directory of the Debian package archive. Or
  `mips` if you want Big Endian because the `el` suffix obviously means Little
  Endian. Duh and or hello
* Install QEMU
* Create a disk: `qemu-img create -f raw disk.img 10G`
* Format it: `mkfs.ext4 disk.img`
* Boot it: `qemu-system-mipsel -M malta -kernel vmlinux-3.16.0-4-4kc-malta -initrd initrd.gz disk.img -append "root=/dev/sda" -nographic -m 1024`.
  Yes `-M malta`. Then it emulates the [MIPS Malta][malta] which is what our
  kernel is targetting
* Run through the whole installer (things will be slow)
* Boot it and make SSH in the guest available as a port on the host: `qemu-system-mipsel -M malta -kernel vmlinux-3.16.0-4-4kc-malta -hda disk.img -append "root=/dev/sda1" -nographic -m 1024 -net nic -net user,hostfwd=tcp::10022-:22`

Once everything was up and running I copied over the compiled result of a tiny
Go program that was just doing `net.Listen(...)` and ran it, fully expecting it
to bork. It didn't. Not a single issue.

### strace

At this point I was pretty annoyed. So it seems that something did indeed
change between 2.6.22 and 3.16.0 that made this bug go away. Considering the
wiki stated 2.6.23 and up should work, I should probably do this again with
a 2.6.23 kernel and see what gives.

As I took a break and rambled about this a bit on IRC someone pointed out I
should just `strace` it and see where it breaks. An `opkg install strace` later
and sure enough: `socket(AF_INET6, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, IPPROTO_IP) = -1 EINVAL (Invalid argument)`.

Turns out, [`FD_CLOEXEC`][cloexec] (which is what [`SOCK_CLOEXEC`][sock-cloexec]
is telling us to set) is new since 2.6.23, whereas the socket option itself
was added in 2.6.27. What it does is set the `close-on-exec` flag on
the file descriptor. This means that when we later call any of the `exec*()`
family of calls we don't leak those file descriptors to child processes. This
is great, especially in things like long-lived servers, but unfortunately just
setting the option instead of properly checking if we can do so means that any
code that does a `net.Listen()` will break if ran on Linux with a kernel older
than 2.6.23.

Now I could've stopped there but obviously not. I wanted to be able to run
the Prometheus Node Exporter, and generic Go code, on that router. I could've
picked Python, Perl, Ruby, rewrite it in Lua I could actually understand and
all would've been over with. But where's the fun in that?

## DD-WRT

Onwards to the next adventure, getting DD-WRT to run. When looking through
the DD-WRT site I could only find really old builds but it turns out that
what you should just get is the latest beta from their FTP. A quick browse
through the forums showed that others had the latest version running in the
AC66U without issue and that it came with a 3.10 kernel! After a few hours
of frustration (it turns out you need to flash 26339 first otherwise your
5GHz will be broken) I finally had everything running.

Uploaded the compiled node exporter, ran it and nothing. It just hang there.
A quick peak into `dmesg` and: `FPU emulator disabled, make sure your toolchainwas compiled with software floating point support (soft-float)`
Turns out that for whatever the hell reason the DD-WRT builds aren't built
with FPU emulation enabled for MIPS. I don't know why. It seems stupid and
actually breaks a lot of things including other software available in Entware.

## OK, now what

At this point, I'm kinda done. I can't get it to run on the Merlin firmware
b/c the code from ASUS it's built on lacks `FD_CLOEXEC` and `SD_CLOEXEC`
support. I could backport support for it but it's unlikely a patch will get
accepted since I'm probably the only person in the world who cares about
being able to run Go code on the AC66U.

I can't get it to run on DD-WRT b/c FPU emulation is missing. There is a way
to [use a different compile toolchain and gccgo to build Go programs for
DD-WRT][ddwrt-go], apparently, but after having already spent more than a
day on this that felt like another rabbit hole I just didn't want to go
down.

## Back to SNMP

The reason I went down this rabbit hole in the first place is because I
just wanted to be able to accurately monitor my WiFi access point. After
some tea it occured to me that with any luck, SNMP on DD-WRT might
actually behave properly and I could go back to just scraping it that way
with the [SNMP Exporter][prom-snmp] the Prometheus folks have built.

Turns out my hunch was right and I can easily scrape all the necessary
counters every 5s with no meaningful impact on the router's CPU usage, all
while running a pretty impactful speedtest. The counters continue to
correctly increment under heavy load and my graphs and gauges in Grafana
reflect reality pretty near real-time.

Victory!

## Conclusion

In the end, I learned a few things:

* Go 1.8 can compile to 32-bit MIPS, and it works but you need a Linux kernel
  \>= 2.6.27, probably even 2.6.32 to be on the safe side
* Even something that appears so basic, standard and boring on the outside can
  change, or gain a new feature that's taken advantage of, in a kernel point
  release that `.22` vs. `.23` does actually matter
* `strace` first, QEMU later
* Flashing DD-WRT is a bit of an adventure, read the wiki and forum
* Router firmware can have the most useful bits and bobs missing while,
  to me useless, other things are available
* Sometimes you won't be able to have your cake and eat it, but if you go
  back to basics you might still be able to claim victory

Once this unit gives out I think I'm going to do a bit more reasearch before
I buy a new one. Find a modern unit, with an ARM CPU instead of MIPS and
figure out if it's missing anything else that I would need to run some Go
code on it. I'd still want to run the node exporter on it as an exercise but
I'd probably stick with SNMP in the future too if it works as expected.

SNMP, when it works, is pretty damn useful. DD-WRT also [exposes a number of
other things through SNMP][ddwrt-snmp] that are useful to monitor for.

This does have me wanting to try to build my own router firmware/OS that, aside
from the Linux kernel, has its components written in Go. With proper APIs
and everything so you can automate it all. Seems like I have something to do
during my next vacation :).

[owrtexp]: https://github.com/jschornick/openwrt_exporter
[di-mipsel]: http://ftp.se.debian.org/debian/dists/stable/main/installer-mipsel/current/images/malta/netboot
[build-mips]: https://github.com/prometheus/node_exporter/commit/bb9d4ade0b677d7f84deec9c354e372edba6a2ec
[linux-26]: https://github.com/golang/go/wiki/MinimumRequirements#linux
[malta]: https://www.linux-mips.org/wiki/MIPS_Malta
[cloexec]: https://www.gnu.org/software/libc/manual/html_node/Descriptor-Flags.html
[sock-cloexec]: http://man7.org/linux/man-pages/man2/socket.2.html#DESCRIPTION
[ddwrt-go]: https://github.com/CodeMonk/dd-wrt-go
[ddwrt-snmp]: https://www.dd-wrt.com/wiki/index.php/SNMP#Known_OID.C2.B4s_via_SNMP
[prom-snmp]: https://github.com/prometheus/snmp_exporter
