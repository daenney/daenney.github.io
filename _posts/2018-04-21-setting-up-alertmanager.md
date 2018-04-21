---
layout: post
title: "Setting up Prometheus Alertmanager"
categories: monitoring prometheus alerting
---

I have a pretty standard Prometheus, bunch of exporters and Grafana setup at
home. This is mostly used to monitor different aspects of my house, like the
exporter I have for power usage. However, while trying to figure out
the cause of a [node exporter crash][n] I found myself in need of an alerting
system, so that it could tell me when the node exporter crashed instead of me
just checking on a daily basis to see if it had.

Thankfully there's the Prometheus Alertmanager which neatly integrates into
the whole ecosystem I already have. However, configuring it turned out to be
a bit more of a pain in the ass, mainly b/c the configuration is split up
between Prometheus and Alertmanager itself. And the docs are rather sparse.

## Getting Alertmanager up and running

I run most of these components through Docker, so I created a unit file like
this:

```
[Unit]
Description=Prometheus Alert Manager
After=docker.service
Requires=docker.service

[Service]
ExecStartPre=-/usr/bin/docker rm alertmanager
ExecStart=-/usr/bin/docker run \
                           --name alertmanager \
                           --read-only \
                           -p 9093:9093 \
                           --expose 9093 \
                           -v alertmanager_data:/alertmanager:rw \
                           -v /etc/docker/config/alertmanager:/etc/alertmanager/:ro \
                           prom/alertmanager:v0.14.0 \
                           --config.file=/etc/alertmanager/alertmanager.yml \
                           --storage.path=/alertmanager \
                           --mesh.listen-address="" \
                           --web.external-url=https://your.domain.tld/alertmanager
ExecStop=-/usr/bin/docker stop alertmanager

[Install]
WantedBy=multi-user.target
```

Don't forget to also create the volume with a
`docker volume create alertmanager_data`, and adjust the path to where you
want to store the configuration file on the host too. I've put Alertmanager
behind a reverse proxy, hence the `--web.external-url` parameter. I'm also
disabling mesh by setting `--mesh.listen-address=""` b/c I don't have more
than a single Alertmanager running at home.

Now, lets start with a very basic Alertmanager config, enough for it to start
but not push alerts to anywhere just yet. Put this in `alertmanager.yml`:

```yml
route:
  receiver: dummy

receivers:
  - name: dummy
```

And now `systemctl daemon-reload; sytemctl start alertmanager`. That's all
you need. Take a look at `journalctl -u alertmanager` and ensure it starts
up. At this point you can reach it on http://localhost:9093 or whatever you
set `--web.external-url` to, but don't forget to configure the reverse proxy
first.

## Hooking up Prometheus and Alertmanager

Next, we need to actually tell Prometheus that there's an alertmanager it can
use when one of the alerting rules trigger. To that end, update your
`prometheus.yml` with this:

```yml
rule_files:
  - 'alerts.yml'

alerting:
  alertmanagers:
    - scheme: http
      path_prefix: /alertmanager
      static_configs:
        - targets: ['ip-of-alertmanager:9093']

```

I'm using a `static_configs` here to manually specify the target, but you can
use all the usual discovery mechanisms available to you in Prometheus too. The
`rule_files` is an array of files where we can find our alerting definitions.
When a relative path is given, it's relative to the location of
`prometheus.yml`. Also note that you don't need `path_prefix` if you haven't
specified `--web.external-url` or if `--web.external-url` does not include a
path.

With that done, you can create an empty `alerts.yml` and restart Prometheus.

## With their powers combined

Alright, so the reason I went down this road in the first place is
because I wanted to be informed when a node exporter stopped reporting in.
This rarely happens at home and either means the network is severely broken,
or the exporter is dead.

To that end I added an alert in `alerts.yml` like this:

```yml
groups:
  - name: default
    rules:
    - alert: InstanceDown
      expr: up == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        {%- raw %}
        summary: "Instance {{ $labels.instance }} down"
        description: "{{ $labels.instance }} of job {{ $labels.job }} has been down for more than 5 minutes."
        {% endraw %}
```

Alerts, like recording rules, are grouped in groups. You need at least 1 group
and you can set the name to whatever floats your boat. Then you'll have to add
1 or more rules which we do by providing an array of alerting `rules`.

I configure my alerts in the v2/YAML format, but there's also the older v1
format. You'll likely run into it if you find blog posts with examples from
before mid-2017. v1 looks more like SQL statements, but maps really easily
onto the v2 format.

In this case, the alert is named `InstanceDown` and in order to figure out if
that's the case it executes the `up == 0` PromQL `expr`. It'll fire once this
is true for more than 5 minutes and attaches a severity label of `critical` to
the alert. Finally we specify the `summary` and `description` of the alert,
which are passed on to Alertmanager.

This works, but... we haven't configured Alertmanager to poke us yet, so right
now all you'll see is the alert in Alertmanager's web UI. In my case I wanted
to use [Pushover][p], so I created a new application in my account, put the
token and user key in my `alertmanager.yml` and restarted it:

```yml
route:
  receiver: pushover

receivers:
  - name: pushover
    pushover_configs:
      - token: app token
        user_key: your user key
```

As you can see `pushover_configs` is an array too, you can repeat that block
multiple times to add more people/systems to push to. You can also have more
types of receivers in a single receiver. There's nothing stopping you from
also adding a `pagerduty_configs` and `email_configs` to the same receiver,
though you should rename the receiver at that point.

Since I don't specify any route matches for any alert, Alertmanager will push
every alert it gets through the default `receiver`, the one configured in the
`route` section.

Last but not least, probably want to test this. There's no button to fire off
a dummy alert, but `curl` will do the trick:

```shell
curl -H "Content-Type: application/json" -d '[{"status": "firing", "labels":{"alertname":"TestAlert1"}}]' localhost:9093/alertmanager/api/v1/alerts
```

In a couple of seconds you'll get a push. B/c I set `status: firing` it'll come
in as a high priority alert through Pushover that you'll have to explicitly
acknowledge.

## Next steps

This is just the tip of the iceberg of what you can do with Prometheus' alerting
rules, paired with Alertmanager's routing capabilities. At this point you have
a working setup you can now experiment with.

The full capabilities of alerting rules are documented [here][ar], and over
[here][am] you can find the docs on routing rules in Alertmanager. I highly
recommend using the [Routing Tree Editor/Visualiser][rtev] as you go along.
Do be careful about pasting secrets in there (the tree is computed
using JS though, so nothing should leave your system).

[n]: https://github.com/prometheus/node_exporter/issues/870
[p]: https://pushover.net/
[ar]: https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/
[am]: https://prometheus.io/docs/alerting/configuration/
[rtev]: https://prometheus.io/webtools/alerting/routing-tree-editor/
