---
layout: post
title:  "Puppet and IntelliJ"
categories: puppet intellij
---

Part of the fun of Puppetconf is getting to talk to so many people and
learning clever new tricks from each other. I knew IntelliJ had some
support for writing Puppet code but as [Travis](https://twitter.com/tefields)
showed me it's been greatly improved.

If you're running IntelliJ you'll need to install both the Ruby and the
Puppet plugins. If you're on RubyMine only the latter is needed.

By default the Puppet plugin handles single modules really well and
gives you things like code completion and refactoring support for your
classes and (defined) types. If you have dependent modules which you
have declared in your fixtures file and run a `rake spec_prep` IntelliJ
will even give you code completion for those too.

But if you have a monolithic Puppet repository with all your modules
IntelliJ is lost out of the box. It turns out though, by tweaking just a
few simple settings, you can get it to work.

In IntelliJ select "Create new project" and then use the Ruby type. Name
it whatever you like (Puppet perhaps?) and point it to your monolithic
Puppet repo. Click finish and open up the project.

Right-click on the `modules/` directory and choose "Mark Directory As
&gt; Sources Root". This doesn't actually achieve anything directly from
what I've been able to gather but it probably helps IntelliJ somehow.
The last thing we now need to do is tell IntelliJ where all the modules
are installed so it can discover them for things like code completion.

Go into your Project settings and navigate to "Languages & Frameworks
&gt; Puppet". Change the language level from 3.X to 4 depending on what
you're using. Next go into the "Environments" section and uncheck
"Synchronize environment with VCS branch name". Edit the production
environment and uncheck "Use default modulepath" and change the
modulepath to point to the `modules/` directory inside your Puppet
repository.

Save the changes and done. Now, open up any Puppet manifest file and try
declaring a new APT source. Assuming you have
[puppetlabs-apt](https://forge.puppetlabs.com/puppetlabs/apt) installed
once you start typing the first letter of a parameter a code completion
box will pop up to help you out.
