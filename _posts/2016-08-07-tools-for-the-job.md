---
layout: post
title:  "The right tools for the job"
categories: foss community opensource
---

Every now and then I find myself in discussions with people around which tools
we should use for what job. This comes up especially often in the context of
FOSS with regards to communication platforms. Do we use IRC, Slack, Gitter?
Also, are mailing lists still a thing? Should we have a Discourse instead?

Fairly often the reaction of people will be "no you can't use Slack, use FOSS
tools for FOSS projects". Up to a point I agree. It really irritates me that
by now I have more than 10 Slack accounts whereas I'm in about 30 channels on
Freenode with no additional account management headaches. Ideally we'll be able
to use FOSS projects to power all of this. But just because something is
proprietary doesn't make it a bad fit.

The most obvious example is GitHub. It is entirely proprietary but
through webhooks provides most people with the necessary extension points.
GitHub has also been instrumental to the rise of open source projects and
Git in general. Without it the FOSS landscape would look very different.

Of coure, GitLab is also around nowadays and a very nice alternative, fully
open source. But it doesn't quite have the traction GitHub has and most
people will assume that if it's a FOSS project it's likely on GitHub. There's
also Gogs if you're looking for a lighter alternative and Mercurial has code
browsing solutions too.

If your core values are "opensource way or the highway" that's fine and you
can tailor your selection of tools based on that. But if that is the case,
don't then go host your code on GitHub but get mad at people over using Slack.

However, for me, the most important question to ask when deciding on where to
host your code, what communication channels to use etc. is "what will help your
project grow". Depending on what your project is and who your likely users and
contributors are, that can be BitBucket and HipChat. Or GitHub and Slack. Or
GitHub and a IRC channel on Freenode plus a Google Groups mailing list. Or
carrier pigeons delivering patches.

I would prefer to use a fully open source code hosting solution but that
shouldn't go at the expense of the project or the contributors. They're one
of the most important factors to keeping your project growing and that should
carry a lot of weight in any decision you make around it. If Slack solved the
account management headache I would probably use it too, considering the amount
of traction they have and it otherwise being a rather pleasant product with an
easy way to integrate additional services. Sure it's fun to write IRC bots but
at some point I'm done with it.

For the forseeable future I'll be hosting my public projects on GitHub, because
that gives them the most exposure and a bigger chance of having a larger
impact and receiving contributions. I'll probably also keep using IRC and Gitter
but not Slack. Gitter provides a good alternative to Slack without the account
management headache and the IRC bridge is somewhat uesable.

Hopefully, eventually, that toolbox will change for a fully open source
toolbelt with a good UX and low bar of entry for any contributor.
