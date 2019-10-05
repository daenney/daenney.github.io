---
layout: post
title:  "PGP, one last try"
categories: pgp gpg security
---

**Update**: I've long since given up on PGP. It's just not worth it. Ignore
this post.

Over the years I've tried to use PGP multiple times. However, I've
always failed miserably at managing keys and understanding the lifecycle
involved. This is evident by searching the keyservers for my name, it'll
turn up a few rather idiotic and dubiously keys. None of them should be
used except for one,
[0x18D40820FA0EE03C](https://daenney.github.io/gpg/).

These failures with PGP are in part my fault for not correctly
understanding what I was doing and part because of the horrendous UX of
the gpg tools and the documentation that comes with it. A lot of
tutorials, especially at the time, totally ommitted things like store a
revocation certificate, store/backup your master key offline etc. while
happily encouraging you to just push your key out.

After spending a few hours every day of the week reading up on some
resources around PGP and a number of tutorials around generating a good
and secure key pairs I decided to give this one last try. If I can't
make it work this time, I'm done.

I am taking a slightly different approach to PGP than usual, which
resulted in the lovely [igalic](https://twitter.com/hirojin) commenting
on this by saying:

> why do you /always/ have to be difficult?
>
> -- <cite>Igor Galić</cite>

Contrary to what most people do my key only has one UID, without an
associated e-mail address.

I am me and the keypair that I've generated is supposed to be used to
authenticate messages as coming from me or to encrypt content for my
eyes only. My e-mail address doesn't help to establish identity at all
or that that message is in any way from me. That same key should be
usable to authenticate/encrypt messages exchanges over Facebook,
Twitter, e-mail or by telepathy. Not all of these are identifiable by an
e-mail address.

## Keypair requirements

In order to not run into the same trouble as before I decided that:

-   My master key will be generated and stored on an encrypted
    USB drive.
-   My master key will never be copied off that drive (though at times
    will be loaded into memeory if I have to sign another key).
-   My master key will only ever be able to certify other keys.
-   My master key will expire in 5 years because I really hope that by
    then we have a better solution. If not I can always extend it.
-   I'll have three separate subkeys, for authentication, encryption
    and signing.
-   These three subkeys will be generated and stored on an OpenPGP Card
    compatible device and will never leave that device.

For the device that generates and stores my subkeys I decided to go with
a [Yubikey NEO](https://www.yubico.com/products/yubikey-hardware/yubikey-neo/yubikey-neo-u2f-2/)
that I happened to have. Besides OpenPGP it also supports FIDO U2F
and can function as an OTP generator. If you had to buy one now I would
suggest buying a
[Yubikey 4](https://www.yubico.com/products/yubikey-hardware/yubikey4)
instead as that one allows you to generate 4096 bit RSA subkeys, the NEO
is limited to 2048. Keys generated with Elliptic Curve Cryptography are
not supported by either model. Considering that a lot of people are
still on OpenGPG versions older than 2.1.0 they're not a very practical
choice either.

## Keypair generation and storage

There is a lot of content avaiable on how to do this and I'm not going
to repeat it here. Read
[Mike English](http://spin.atomicobject.com/2013/09/25/gpg-gnu-privacy-guard/)'s
excellent set of blogposts on the topic and
[this one by Eric Severance](https://www.esev.com/blog/post/2015-01-pgp-ssh-key-on-yubikey-neo/).

I adjusted them a bit to fit my needs in the sense that:

-   Set up some
    [sane settings](https://github.com/daenney/gpg/blob/gh-pages/gpg.conf)
    in `gpg.conf`.
-   Generated the master key myself (so not on the Yubikey) and stored
    directly on an encrypted USB drive (set `GNUPGHOME` environment
    variable to point to your desired location when generating it and
    don't forget to copy a sane `gpg.conf` to that location too) .
-   Generated a revocation key and distributed a few copies of it so
    that I can always revoke the key should it be compromised or if I
    lose access to it.
-   Public key is stored on [GitHub](https://github.com/daenney/gpg/) and
    hosted through [GitHub Pages](https://daenney.github.io/gpg/).
-   Set `keyserver` on the Yubikey to point to the location of my key on
    the web and then imported it with a `fetch`.
-   Generated the subkeys on the device itself (`addcardkey`).

## Final words

It took me a lot of time in reading and trying this all out, combining
different blogposts to reach the solution I deemed secure enough for my
needs and still usable. I did this process a few times over and probably
still fucked up somewhere.

The key with id 0x18D40820FA0EE03C is stored on
[GitHub](https://github.com/daenney/gpg) and leveraging GitHub Pages is
available on https://daenney.github.io/gpg. It has also been pushed out
to the GnuPG/sks-keyserver pool of servers. If you sign my key and push
it back out do let me know (you really shouldn't sign a key blindly
anyway) so I can export it and update the copy on Github.
