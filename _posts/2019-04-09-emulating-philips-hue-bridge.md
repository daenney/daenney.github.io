---
layout: post
title: "Emulating a Philips Hue bridge"
categories: iot
---

As part of my [home automation][ha] I wanted to emulate a Philips Hue bridge.
The reason for that is that a lot of things provide out-of-the-box integration
with Philips Hue. Aside from that, there's a ton of apps and other cool
things in the Hue ecosystem I wanted to unlock.

However, we use the IKEA Trådfri system at home, even though we do have a
first generation Philips Hue bridge. The reason for switching to the IKEA
one was:

* Local-only API, no cloud involved at all
* Bulbs are cheaper, especially at the time, making it feasible to equip
  the whole house with them without breaking the bank
* You can observe/subscribe to events on the Trådfri gateway, which fits in
  more neatly with our usage of MQTT than the HTTP polling approach Philips
  took with the Hue
* Security. Trådfri uses CoAP+DTLS with a random Pre-Shared Key printed
  on the bottom of the device. You need physical access to the device
  to get this key and all communication with the gateway is always
  encrypted

The rest of this post will take a look at what went into building a Philips
Hue v2 (the square unit) emulator. I wanted to emulate the Hue v2 because it
has a newer API with more capabilities. Only the v2 bridge supports the new Hue
Entertainment API so I can sync the light bulbs to what I'm watching on my
screen. The other requirement was that the emulated bridge had to be good
enough to fool the official Philips Hue app.

## API

The first thing needed to do is figure out all the API endpoints to implement,
what their response types are etc. Philips does a fairly decent job of keeping
the documentation on their Hue developer site up to date. This makes it possible
to figure out what you need to do.

The Hue API documentation is not complete though, and many of the response
examples show all possible keys and values for the JSON blob an endpoint can return.
Many key/value pairs are dependent on some other condition, like the bulb
type, or the group type etc. Figuring this out is largely trial-and-error though
having a Hue v1 bridge to test against proved useful. You can also find many
examples of Hue API responses in GitHub issues, Gists and pastebins.

The Hue API is also very peculiar in places. It always returns a 200 OK even on
errors, but then has a body with the error information encoded as JSON. I don't
mind the body, it's helpful, but would it have killed you to return a 4XX or 5XX
status code too? There's other oddities too. The `/lights` endpoint returns a
map of all lights, where the keys are **stringified** incremental IDs (though they
don't have to be, turns out). Lots of things are strings in the API for which
real types exist. Other funky shit includes the special `/groups/0` which always
returns all devices on the bridge but never seems to be used.

I went through a cycle of 😕 😲 🤯 😖 😵 🤮 😡 trying to faithfully reimplement
the Hue API. What really bugs me is that when the Hue v2 bridge came out they
had the opportunity to fix a lot of this, but didn't. It would also be really
nice if the Hue API came with an OpenAPI spec. That would drastically improve
the docs and make it feasible to auto-generate most client implementations or
scaffold a server.

## Authentication

In order to be able to talk to the Hue API you need to register with it first. This
is done by posting some JSON to `/api` which returns a `username`. This username
is really a token, not so much a username, and any subsequent requests are done to
`/api/<username>/<endpoint>`. Why oh why the token ends up being part of the URL
is a mystery to me, it could have just been an HTTP header. At least the whole API
is JSON over HTTP and returns correctly formatted JSON too.

When you post to `/api` to register, the request will be rejected if you haven't
pressed the link button in the past 30s. So gaining access to the bridge
effectively means you need physical access to the device. This may seem perfectly
secure so you might be wondering what that "security" bit was about in the
introduction. We'll get into that in the next section.

## Security

There is not much point to the whole registration thing if the token flies over
the network plain text. However, that's exactly what happens with the Hue v1
bridge. As long as someone manages to capture a single HTTP exchange with the
Hue bridge (the official Hue app polls a number of endpoints every 2 seconds)
they'll have access to your bridge. 🎉

They attempted to rectify this with the Hue v2 bridge, but the solution is
still a bit dodgy. The Hue v2 API is accessible both over HTTP on port 80 and
HTTPS on port 443. The way it works is like this:

* The client hits `/api/nouser/config`, plain text. When the Hue app doesn't
  a token yet it uses `nouser`. This returns some basic information about the
  bridge, like its IP, MAC, API and software version (but nothing about lights,
  groups etc.)
* The client then talks to the rest of the endpoints over HTTPS, with the Hue
  bridge returning a self-signed cert with a subject of
  `C=NL/O=Philips Hue/CN=$MAC-WITHOUT-COLONS` and the serial being the integer
  representation of that same `$MAC-WITHOUT-COLONS` base 16 🙄

It's trivial to MITM this, or create your own fake cert that the
official Hue app will gladly accept. All you need to do is ensure that the `mac`
returned by the config endpoint matches the certificate. It doesn't even have to
be the real MAC of the device.

This makes the Hue v2 bridge much less susceptible to eavesdropping and stealing
of credentials. However the ease with which you can MITM this is still concerning.
It might have been nicer to burn a cert in the bridge at the factory and pin that
in the app. Short of being able to extract the keys from the device it would've
become much harder to MITM it, or to fool the Hue app into talking with an emulated
bridge. The IKEA approach is fairly elegant too, using a PSK instead. This also
avoids the weird registration thing you need to do but of course once you know
the PSK you can't prevent someone from accessing it without replacing the
physical gateway.

The Hue Entertainment API, which like IKEA takes the DTLS approach, uses the PSK
strategy. When you register with the bridge, using the `/api` endpoint over
HTTPS, you can additionally request a client key that is entirely separate from
the username/token. That client key is then used as a PSK for the DTLS part.

## Discovery

In order to talk to the bridge, you need to know its IP first. The Hue developer
documentation informs us that you can discover the bridge in 3 ways:

* Do an SSDP discover (UPnP)
* Hit https://discovery.meethue.com/ (Philips cloud) that will return
  all internal IPs and MACs of all bridges that have the same external IP as the
  IP the request to the Hue discovery API came from. Effectively a little agent
  runs on each hardware bridge that publishes this information to Philips. Kinda
  like the old dynamic DNS clients you had
* Find everything with port 80 open on the network

Once you got an IP out of one of those approaches you hit the `/descripiton.xml`
endpoint, parse the response and check some fields to determine if it's a Hue
bridge.

Additionally the docs mention that you can use mDNS by looking for SRV records
on `_hue._tcp.local` but the bridge doesn't seem to do so nor does the Hue app
use it as part of its discovery strategy. My emulator does have an mDNS
responder though, just in case things do start to use it.

There is also an interesting discrepancy between the Philips Hue app and the
previous Philips Hue (v1 bridge) app. The former does not seem to do SSDP
discovery at all and immediately proceeds to port scan my network, whereas
the old app does. I've confirmed this with packet captures but Philips Hue
insists their current application does use SSDP. It might still be listening
for SSDP notify/broadcasts but it does not do SSDP discovery. Vendors lie,
or at the very least appear (wilfully) ignorant of their own products'
behaviour. But you can't hide from `tcpdump` 🤷.

## Bulb emulation

My Hue emulator leverages the same protocol as explained in the
[home automation][ha] post. This means that it's not really aware of the fact
that it's emulating IKEA bulbs, or that those bulbs actually come from the
IKEA Trådfri gateway. Thanks to this is also exposes some light strips that
are exposed by a controller directly attached to the strips running on a
NodeMCU.

The emulator discovers all "lightbulb" accessories on the MQTT
broker and looks for the `hue`, `saturation`, `colorTemperature` and
`brightness` characteristics. If `hue` and `saturation` are found it fakes
a Hue A19 Extended Color bulb. `colorTemperature` is exposed for bulbs
that can display a range of whites, from roughly "hospital" to "sunset"
and fakes a Hue White Ambiance bulb. Anything else, i.e a bulb for which
we only found the `brightness` characteristic, is emulated as a regular Hue
White bulb 💡.

The Hue A19 and the Hue White Ambiance are exposes as a "mixed" function
bulb with the "sultanbulb" archetype. The only real thing this seems to
affect is the icon that is used to represent the light. The Hue White
gets the "classicbulb" archetype which gets us a different icon making
them a bit easier to distinguish in the Hue app.

## Groups and Rooms

The Hue app is rather stubborn and demands all your lights be assigned
to a room. Since the bulbs we have on MQTT are in reality groups we
simply create a room for each bulb and assign the bulb to it. Because
we gave our groups names that match the hard coded list of rooms
Hue supports we can infer the `class` of the room. By setting the group
named "Kitchen" to the "Kitchen" `class`, case sensitive and capitalised
I kid you not, we get a nice icon in the app, a cooking pot.

The insistence of having every light assigned to a room is a bit
annoying though. It would be fine to let people not organise them in
groups. It also seems that nowadays the Hue app doesn't let you
create a regular LightGroup group anymore, all groups are Rooms. This
makes it a bit hard to organise lights in arbitrary constellations
that might not map nicely to rooms. It's not been a problem in real
life though.

## Sensors

I haven't gotten around to supporting sensors yet, but I'd like to at
least at support for our motion and contact sensors. They're also exposed
using the same protocol on MQTT so this shouldn't be hard.

## Conclusion

The main challenge in building this bridge wasn't recreating the API,
but getting it to work with the official Hue app. The switchover to HTTPS
for v2 isn't really documented anywhere so for the longest time I couldn't
figure out why it never moved passed the initial queries to `/description.xml`
and `/config`. A lot of this would probably have been a lot harder if not
for the emulated Hue bridge in [Home Assistant][haas] and the code of the
[diyHue][diyhue] projects. That latter one came in especially handy to
figure out what I had to stuff in the TLS cert for the Hue app to be happy.

With a couple of evenings of work I have a pretty functional Hue bridge
now that works with the official Hue app. I've yet to implement the
functionality to control the bulbs through the Hue API so for now it's
read-only. I want to reorganise and have tests for this code before I
add all of that.

Once that's done I'm planning to add support for Hue Entertainment API.
That will require adding a UDP listener, figuring out DTLS and adding
support for the Hue Entertainment API packet format.

[ha]: https://daenney.github.io/2019/04/07/home-automation
[haas]: https://www.home-assistant.io/
[diyhue]: https://diyhue.org/
