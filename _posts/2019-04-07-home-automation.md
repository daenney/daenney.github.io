---
layout: post
title: "Home Automation"
categories: iot
---

I'm addicted to home automation. There. Said it. But it's just such a
tremendous amount of fun to play with. I'm pretty sure it's the SRE in
me. Why do anything by hand when you can have computers do things for
you? Why turn on the lights when you get home when it can happen
automatically? Turn on the lights when you enter the bathroom? Barbaric!
Turn them off? I've git better things to do! Why not wake up to the smell
of freshly brewed coffee every morning instead of having to get out of bed
first to turn on the coffee machine?

However, as with most IoT things, security and privacy are a big problem
because vendors regularly screw this up. Or make their products completely
unusable without signing up for their, sometimes paid, cloud service.

In order to enable my hobby we decided to design our own home automation/IoT
control plane. Yes. Yes we did. There were a few key requirements:

* Local first: everything needs to work without internet access
* Private: no tracking of what we do, or when we do it
* Secure: TLS and things like that
* Cloud optional: some, opt-in, cloud-powered features
* Abstracts away vendor-specific APIs and protocols

Lets go through them.

## Local first

This shouldn't come as a surprise but basically: everything needs to work
with the internet down. This immediately discards most Google powered stuff
as it just won't work. Fine by me because privacy isn't really a
thing they're known for anyway.

Select IoT devices that you can talk directly to yourself using an API. For
example I have both a Philips Hue and an Ikea Trådfri bridge (more on that
later), a Raspberry Pi with a Z-Wave stick and a 433MHz receiver. That covers
a huge amount of devices that can all work without $vendor cloud.

When that won't work, build your own. My robovac is dumb, no app, just IR,
controlled by a Raspberry PI with an IR blaster. That IR Pi can also be used
to turn on/off and control all kinds of devices like your TV, speakers etc. It
replaces the need for something like a Logitech Harmony Hub.

## Private

This more or less follows from "Local first". Since everything works locally
and is not dependent on some cloud API, what you do and when you do it stays
private. Maybe it could be useful if Google knew what time I turned my
lights on and off, but also maybe not. Same for Philips by the way, the
bridge isn't hooked up to their cloud at all (no remote API etc).

The one exception here is Apple with HomeKit. It provides a few useful
features (particularly the geofence), that we rely on. But Apple has built
a reputation as a very privacy concious vendor and I haven't seen anything
to disprove that. It's also important to note that just about everything in
HomeKit is still local and access is mediated by a central iOS or tvOS
device in your home. Even with the internet down, HomeKit still works.

## Secure

I mean. I can't even really.

There's two things that are reasonably secure:

* IKEA Trådfri: CoAP over DTLS (UDP+TLS)
* Apple HomeKit

Just about everything else relies on the fact that it's "inside your
home" so behind a NAT. Everything flies over your network in plain text and
most security schemes and keys are derived from MAC addresses.

This is fixable by putting IoT devices in their own VLAN. Which
incidentally also ensures the "Local only" thing because there is no path
to the outside world.

Also, just no on the digital doorlocks. Don't.

## Cloud optional

As mentioned in the "Privacy" bit already, we do leverage HomeKit for
triggering certain actions based on geofences. It's also one of two ways we
have remote access to the house. The other way is a custom web app that
sits behind an SSO Proxy backed by our LDAP infra (which is hosted at
home so if that dies no more access this way).

## Abstractions

This is the crucial bit. I'm also really happy how it turned out.

We wanted a way in which any interested party could interact with any and
all devices in our home. The problem is, every vendor has their own bridge,
protocol and API. This means that everyone needs to understand everyone,
discover each other and be able to talk to each other. This becomes a nightmare
quickly and you end up re-implementing the vendor API and protocols in every
component or you end up with 1 big thing that can't fail.

Instead, we leverage Apple's HomeKit specification. The HomeKit spec is pretty
expansive. It gives us a generic way to describe devices and their capabilities.
We mapped its accessories and characteristics into a JSON representation and chose
MQTT as our transport. Using MQTT was a very deliberate choice. We wanted something
that you could subscribe to instead of needing to constantly poll for state changes.

Now when you want to turn the light on, you pop onto the MQTT broker, publish
a packet to the bulb's on/off characteristic topic and poof, light turns on/off.
No need to know how to talk to the Hue bridge or the Trådfri gateway anymore! All
you need to do is read and write some JSON, but over MQTT instead of HTTP.

We added a few things HomeKit doesn't do. We needed a way for devices to
announce themselves when they join and announce when they leave. For example
when a device leaves things like its reachability characteristic can be updated
by those that were subscribed to it. We also needed a way to be able to discover
all devices currently registered with the broker.

## Ecosystem

What we then built are device bridges onto MQTT. These bridges effectively
wrap the vendor specific API into our specification and we take care of
translating values and API calls back and forth.

We've built our own software library that abstracts away things like the fact
that MQTT is used as a transport. We can write code without needing to worry
much about the internal mechanics of the system, or a vendor API.

```go
lightbulbs := mqtt.DeviceByType("lightbulb")
for _, l := range lightbulbs {
    l.Feature("on").Set("off")
}
```

And now all the lights are off, whether they're connected over Zigbee, Z-Wave,
WiFi or something else entirely.

### HomeKit

This was the first bridge we built and probably the most complicated and
complex one. It exposes all those HomeKit-as-JSON-over-MQTT devices as
devices behind a proper HomeKit bridge. It's recognised by and works together
with Apple's Home app on iOS and macOS. I can turn the lights on/off using
HomeKit and the Trådfri gateway will do its thing. I can trigger the robovac
or see the temperature in the office. The HomeKit automation works too,
making it automatically turn the lights on when my iPhone reports in as
nearby and turns everything off when the last person leaves.

Nowadays Trådfri comes with its own HomeKit support. This was built two
years ago, just a few months after the original Trådfri release and predates
IKEA's HomeKit support by about a year.

That's one other nice benefit, we're not dependent on any vendor for HomeKit
support. We have plenty of devices in the Home app that don't have HomeKit
support, like our temperature sensors that are reporting in over 433MHz.

### IKEA Trådfri

We have a Trådfri bridge that maps Trådfri groups onto MQTT. It
exposes Trådfri groups as "lightbulb" accessories. This is a tiny bit
cheating but I never have a need to only turn on half of the kitchen lights
so this works fine.

Controlling lights and their colour is now a simple matter of publishing the
right thing on MQTT. We only had to figure out the CoAP+DTLS thing once and
now anyone can interact with them.

### Philips Hue

We have a Philips Hue software bridge, which emulates a v2 bridge. It exposes
as the Hue HTTP API all the devices the Trådfri bridge proxies on MQTT. I can
use the official Hue app with our software bridge to turn a light on/off or
set the color or brigthness on a bulb connected to the Trådfri gateway. If I then
use the Trådfri app or physical remote to change the color, the next time the Hue
app polls our fake Hue bridge you'll see the changes reflected in its UI.

The poll-based nature of the Hue HTTP API is part of why we moved away from Hue and
onto Trådfri. Trådfri lets you subscribe to devices on its bridge. This fits much
nicer with how we're using MQTT and means that the state of a device is almost
instantly updated everywhere, instead of the short but noticeable 2s delay the
Hue app suffers from. Trådfri bulbs, at the time, were also less expensive which
made equipping the whole house with them much more financially bearable. The Hue
bulbs do have a bigger color spectrum and white temperature range but the Trådfri
bulbs turn out to be good enough for my needs.

I never had to teach the Hue bridge anything about the Trådfri gateway or protocol,
only how to take the lightbulb accessory published on MQTT and turn it into a Hue
bulb. It's essentially a Hue-JSON-to-HomeKit-JSON converter. This also means that
anything under the "Friends of Hue" umbrella works despite the fact we don't have
a physical Hue bridge.

Now all that's left to do is implement the new UDP+DTLS based Hue Entertainment
API so my TV can sync with the bulbs.

I'll follow up this post with what it took to build a Philips Hue bridge
emulator. It was wild.

### Z-Wave, 433MHz and IR

Similarly we have a Z-Wave bridge that exposes on/off switches and a bunch of
sensors onto MQTT. If you want to turn one on you don't need to learn anything
about Z-Wave. You get the accessory you're looking for, find the on/off characteristic
topic and publish a message to it. Only the Z-Wave-to-MQTT bridge knows anything
about Z-Wave.

We also have a Teldus bridge that does something similar for 433MHz devices. It
exposes things like temperature and humidity sensors. Sensors for obvious reasons
are read-only.

Last there's a Raspberry Pi that exposes lirc devices onto MQTT. If you want to
turn on the TV you publish a message on MQTT and the IR-bridge will translate
that into IR codes and blast it out through a few diodes. This is how I can turn
the TV on through HomeKit and how Node-RED triggers the robovac on work days.

### Prometheus integration

There's a Prometheus bridge that looks for accessories with characteristics like
contact state, temperature etc. and exposes that using Prometheus' exposition
format. It works like any other exporter in the Prometheus ecosystem. Our central
Prometheus server then scrapes this exporter. We can now see things in
Grafana like current power consumption, temperature, if one of the wireless
sensors is almost out of battery or if a door is open.

Alerts have been set up in Prometheus that through a combination of Alertmanager
and a Matrix webhook receiver notify us. For example if an outside door is open
for more than a certain period of time it fires an alert.

## Conclusion

One thing we haven't tackled yet is voice. So far everything we've built requires
some kind of app to interact with. Thanks to HomeKit we do have Siri
available to us but she is far from customisable.

Building this has been a lot of fun. With everything in place and tooling like
Node-RED we have the ability to build some very fun stuff. It did take a few
tries to get it right, especially when it came to the client libraries which
are still in flux.

It's also been an exercise in frustration. Many vendor specs are incomplete and
their devices don't behave according to spec. One noticeable thing is everyone
needing to have different ways to respresent colour. Between HomeKit, Hue and
Trådfri we need to convert colour representations in all directions.

In the end though it's pretty amazing. Why wait for a future with automated
homes when you can build your own! The future is now :).
