---
layout: post
title: "Arch Linux and firmware/BIOS updates"
categories: linux firmware fwupd
---

One area Linux has made quite a lot of progress in is the ability for people
to get firmware and BIOS updates for their devices. This used to be a massive
PITA but thanks largely to the [Linux Vendor Firmware Service][lvfs] and its associated
tooling (`fwupd`, `fwupdmgr`) this has become a lot simpler. Quite a few vendors
support this nowadays and deliver firmware and BIOS updates through LVFS. Most
of this is thanks to [@hughsie][hugh] so if you run into him, say thank you
or offer him a drink!

Dell is one of the [vendors][v] supporting this initiative and push BIOS,
TPM and Thunderbolt firmware updates this way. However, getting this to work
reliably proved a bit tricky on Arch, so I'm documenting what needs doing
here. Most of this information can be scraped together through the Arch
wiki, this is just a collection of that.

Check where your (U)EFI System Partition (ESP) is mounted by running:

```
findmnt -o TARGET,FSTYPE -t vfat /boot/efi
findmnt -o TARGET,FSTYPE -t vfat /boot
```

If the first command returns a `TARGET` of `/boot/efi`, then that is your ESP.
This is likely to be the case if you use GRUB. Else, the second command should
return with a `TARGET` of `/boot`, which is the mount point of the ESP. This will
be the case if you changed the GRUB defaults at installation time or are using
systemd-bootd to boot your system. If neither command returns you're not
using EFI to boot your system and this guide won't help you.

With the ESP mounted on `/boot/efi`, you can follow this guide but skip
the Configuration section, you also don't need to worry about the minimum
required package versions mentioned in the Installation section. For anyone
with the ESP on `/boot`, you'll need to follow every section to the letter.

## Installation
First things first, you'll need to ensure you have at least `efivar` version
`34` or greater installed,`fwupd` `1.0.6` and `fwupdate` `10`. With older
version of these packages this will simply not work as things were hardcoded
to assume `/boot/efi` and provided no way to override this. The Arch
repositories contain the needed versions from 2018-03-12 onwards.

Start with installing fwupd if you haven't already: `pacman -S fwupd`. It
will automatically pull in `fwupdate` and `efivar` through the dependency
chain.

## Configuration
Now, tell `fwupd` that your ESP is mounted on `/boot` by editing
`/etc/fwupd/uefi.conf` and setting `OverrideESPMountPoint=/boot`. Restart
`fwupd` with `systemctl restart fwupd`.

## Cleanup
In case you had previous installations of fwupd from another Linux
installation, we need to clear that out any EFI variables it might have
left behind. First, check if there's any such remains by running:

```
ls /sys/firmware/efi/efivars/fwupdate-*-0abba7dc-e516-4167-bbf5-4d9d1c739416
```

If that returns anything, execute the following, if not skip this step:
```
chattr -i /sys/firmware/efi/efivars/fwupdate-*-0abba7dc-e516-4167-bbf5-4d9d1c739416
rm -f /sys/firmware/efi/efivars/fwupdate-*-0abba7dc-e516-4167-bbf5-4d9d1c739416
```

## Handling fwupd updates
For some reason when fwupd gets installed it doesn't copy over the necessary
files into the ESP to be able to actually prepare and schedule firmware updates.

First, we need to copy some files over to your ESP:
  * With the ESP on `/boot`: `cp -r /usr/lib/fwupdate/EFI /boot`
  * Otherwise: `cp -r /usr/lib/fwupdate/EFI /boot/efi`

Then create the pacman hooks directory with `mkdir /etc/pacman.d/hooks`.

Finally, link the fwupdate hook to automate the above file copy process as this
needs to happen whenever `fwupd` gets updated:
  * With ESP on `/boot`: `ln -s /usr/share/doc/fwupdate/esp-as-boot.hook /etc/pacman.d/hooks/fwupdate-efi-copy.hook`
  * Otherwise: `ln -s /usr/share/doc/fwupdate/esp-as-boot-efi.hook /etc/pacman.d/hooks/fwupdate-efi-copy.hook`

## Firmware updates

With all of this done, it's time to get updating:

```
fwupdmgr get-devices  # shows which detected devices are supported
fwupdmgr refresh  # refresh update metadata
fwupdmgr get-updates  # list available updates for this system
fwupdmgr update  # do the updates
```

If you use GNOME and have GNOME Software installed, firmware updates will
also show in the Updates tab and clicking on the Install button will now
actually work.

One thing I noticed, the first time after updating and rebooting, my
`/etc/fwupd/uefi.conf` got reset, so do double-check this after you've
run updates and rebooted for the first time. It'll be pretty obvious that
something is broken, `fwupdmgr` will complain about all kinds of filesystem
path issues if this is not correct.

As you can see from `fwupdmgr get-devices`, just about every update requires
you to have AC-power plugged in (in case of a laptop). If you try without it,
the firmware updates will simply fail and you'll have to run `fwupdmgr update`
again and reboot another time to get it to try again.

Good luck and happy updating!

[lvfs]: https://fwupd.org
[v]: https://fwupd.org/vendorlist
[hugh]: https://github.com/hughsie
