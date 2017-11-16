---
layout: post
title: "Thunderbolt security modes and Linux"
categories: linux
---

With my [XPS 13 up and running][xps13] I ran into some issues with the Dell
WD15 (USB 3) dock. It mainly caused my display manager to crash whenever I
would plug it in with (with my external screen attached), except after a fresh
boot. This is of course wildely unhelpful but a colleague told me many folks
had issues with the USB 3 version of the dock and to get a TB16 (thunderbolt)
instead.

So I did and to my astonishment I can now plug in and out of the dock and my
display manager survives every time. Case closed.

Except, not quite.

Thunderbolt 3 has different security modes in order to protect your device.
This is needed b/c if you leave your thunderbolt ports unprotected and your
device unattended someone could plug into a port and interact with your
system, even if you've locked it.

The modes are:
  * none (or legacy): just accept any device plugged in
  * user: user needs to authenticate the device
  * secure: same as user but with an additional random key to automatically
    recognise the device the next time you plug in
  * dponly: only allow for the DisplayPort functionality, nothing else

What you want is to have your device in user or secure mode but before kernel
4.13 you cannot, as there is no support for security modes before then.

Thankfully Arch has kernel 4.13 and onwards available. What you'll
then also need are some thunderbolt userspace tools to help you authenticate
devices when they're plugged in. There is absolutely no GUI support at all
available but there is [a set of CLI tools][tbcli].

The CLI tooling is [available in AUR as the tbt package][tbt]:

```sh
$ pacaur -S tbt
```

Once you've got that installed, reboot, enter the BIOS (hit F2) and change the
Thunderbolt security settings to 'User'. Do **NOT** enable pre-boot or boot
module support, that'll basically downgrade the security level to 'none'.

With that done, boot, fire up a terminal and plug in a Thunderbolt device.
Nothing should happen now (though DisplayPort passthrough might still work).

You can now see Thunderbolt attached devices through `sudo tbtadm devices`.
For the TB16 it'll show you 2 devices, the thunberbolt cable and the actual
dock. You can also look at the topology with `sudo tbtadm topology` which
will show you that the dock is 'behind' the cable.

When listing devices the first column in the output is called the 'route
string'. You'll need that string to approve a device.

In the case of the dock, you need to approve both the cable and the dock,
which I simply did through `sudo tbtadm approve-all`.
Take care when you execute this command to only have the devices plugged in
you want to authenticate and double-check nothing weird is plugged into the
dock before you do it. You can also authenticate one device at a time with
`sudo tbtadm approve <route string>`. If you only want to approve a device
for one time use issue `approve-once` or `approve-all-once` instead. 

Both the cable and the dock are authenticated now and ACLs and udev rules
have been created to automatically authorise the devices the next time you
plug into the dock:

```sh
$ sudo tbtadm acl

d8030000-0000-8718-a294-abd022931118	Dell	Dell Thunderbolt Cable	not connected
d4030000-0092-8d18-2212-fbd5d014f118	Dell	Dell Thunderbolt Dock	not connected
```

Now you should have USB, the other video ports as well as the ethernet port on
the dock working for you!

Do note one thing, once you've authorised the dock anything that gets plugged
into the USB port of that dock will pass through to your laptop. Meaning that
if someone plugs in a malicious USB stick into your dock without you knowing
you've still got a problem. But if someone were to swap the dock out, or even
the cable or try to plug in a different thunderbolt device they'll be out of
luck.

[xps13]: https://daenney.github.io/2017/11/11/arch-linux-xps-13-9360.html
[tbcli]: https://github.com/01org/thunderbolt-software-user-space/
[tbt]: https://aur.archlinux.org/packages/tbt/


