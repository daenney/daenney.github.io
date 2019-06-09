---
layout: post
title: "Arch Linux and the HP Envy x360"
categories: linux
---

* Update 2019-06-09: Performing BIOS updates

I recently decided to get myself a new laptop. Though work provides me with
one, I make a point out of never using it for personal use. It can get a bit
complicated around intellectual property laws. I'm also perfectly fine with
my employer enforcing certain policies on their device that I just don't
want for my personal devices.

For the device itself I decided I wanted a 13" model, with an AMD Ryzen CPU
and Radeon graphics. This was an explicit goal and vastly limited my choice of
hardware. I'm tired of paying premium for Intel CPU flaws and on top of that
getting saddled with the aisling and underpowered Intel HD 620/630 graphics.
Since I run Linux nVidia hardware is out of the question.

This being a personal device I also had no desire to break the bank so anything
over about $1k was out of the question. If I need significantly more compute
power I can SSH into my ridiculously overpowered desktop at home, so there's no
need for this laptop to run a Core i9 and have huge amounts of memory.

I ended up with a HP Envy x360 with an AMD Ryzen 7 2700U and RX Vega 10 graphics.
This is a convertible device, a 2-in-1 laptop with a touchscreen that turns into
a tablet. Pen included.

The device works pretty well out of the box on Linux, but there are a few
caveats:

* The touch screen **does not** work on Linux <5.2, so at the time of writing
  you have to compile yourself a mainline kernel
* A driver for the AMD Sensor Fusion Hub is scheduled for end of summer 2019
  so right now you won't have access to the rotation sensor
* Ensure you update to the latest BIOS first, mine came with a year old version
  that has a few problems. There's also a firmware update for the pen. Don't ask
  me why

For installation instructions, it's pretty much the same as what I documented
when setting up Arch Linux on the
[Dell XPS 9360](https://daenney.github.io/2017/11/11/arch-linux-xps-13-9360).

**Note**: you'll need the `amdgpu` driver, not `i915`.

## Updating the BIOS

You'll need a Windows computer for this and a USB stick, a VM works just fine.
You can then follow the procedure detailed in
[HP's BIOS Recovery](https://support.hp.com/us-en/document/c02693833)
to create a USB flash drive that allows you to update the BIOS.

This means that it's not necessary to keep Windows installed on this machine,
despite the fact that HP does not deliver BIOS updates as EFI capsules and/or
through [LVFS](https://fwupd.org) for the Envy x360.

## Compiling a 5.2+ kernel

A lot of distributions have mainline kernels available and you'll 5.2+ for this
device if you want the touch screen to work. If you don't care for it then you
can just wait until your distribution updates. But then, why did you even buy
this thing?

One other thing of note is that in 5.2 the `rtlwifi` driver has been removed in
favour of the new Realtek RTW88 driver. You need to update your config to include
the following before building a kernel or you'll be without WiFi.

```ini
CONFIG_RTW88=m
CONFIG_RTW88_8822BE=y
```

## Graphics

You'll need the following packages:

* `mesa`
* `vulkan-radeon`
* `xf86-video-amdgpu`

No configuration is necessary.

## Hardware accelerated video

You'll need the following packages:

* `mesa-vdpau`
* `libva-mesa-driver`

For GStreamer to use hardware decoding:

* `gstreamer-vaapi` (VA-API)
* `gstreamer-plugins-bad` (VDPAU)

No configuration is necessary.

Note that if you're running KDE, you should install Phonon with the GStreamer
backend, and not VLC. The VLC backend can't take advantage of all the hardware
decoding capabilities.

## Enabling tablet support

For this you'll need to load the `wacom` module and have `libinput` and `libwacom`
installed. For X11 you'll need `xf86-input-libinput` and `xf86-input-wacom`.
You'll probably have to load the `wacom` kernel module yourself by dropping a file
for it with the module name in `/etc/modules-load.d`

The device will work out of the box on Wayland but you'll have to convince X11 to
use the Wacom driver. Drop the following in `/etc/X11/xorg.conf.d/99-tablet.conf`:

```conf
Section "InputClass"
    Identifier "Elan driver override"
    MatchUSBID "04f3:*"
    MatchDevicePath "/dev/input/event*"
    MatchIsTablet "true"
    Driver "wacom"
EndSection
```

Last thing, you'll have to create `/usr/share/libwacom/elan-2627.tablet` with the
[contents from this PR](https://github.com/linuxwacom/libwacom/pull/95/files) until
a new release of libwacom makes it into Arch.

One thing to note: On Wayland sessions [drawing with the pen does not yet work for
KDE Plasma](https://community.kde.org/Plasma/Wayland_Showstoppers#No_.28wacom.29_Tablet_support).
It works on X11 but if you want to use KDE+Wayland you'll only have touch for now.

After all of this you'll have to reboot.

## Slow pen tracking, erratic touch

When booting Linux I got really erratic behaviour from the touch screen. Any touch
would register a flood of events. They'd usually get interpreted as multiple clicks
so if you touched a header bar the application would maximize/unmaximize a couple
of times. Touching any button would mean clicking it multiple times. The pen was
also dog slow in tracking, it lagged behind all the time.

It took a while to find why and I stumbled upon it by pure chance. Apparently this
happens due to some badly initialised ACPI register. The fix is simple:

* Forcefully power off the device
* Keep holding the power button for another 3+ seconds

After applying that little "fix" I got perfect touch and pen tracking. The fix
persists for me across sleep, shutdown and reboot cycles.

I suspect this is some unhelpful interaction between Windows and Linux and it'll
probably start tripping again after booting Windows. At least it's easy to fix.

## Power saving

I manage to get a good 7 hours out of this device with just some browsing and
basic usage at about halfway the brightness.

I run TLP on it to help ensure it runs a bit quieter and cooler on battery. Even
if you don't, you'll want to boot with `nmi_watchdog=0` as well as drop a file
with `options snd_hda_intel power_save=1` in `/etc/modprobe.d`. If you have no
need for Bluetooth you might also want to blacklist `btusb`.

One other thing I noticed is that the baseline system load is lower by a couple
percent when using Wayland instead of X11. I don't really know why. [As noted
before](#enabling-tablet-support), you'll have to flip to X11 in KDE in order
to be able to use the pen. Or run Gnome, but that will give you a secondary
crosshairs pointer for some reason.
