local addMixin = (import 'kube-prometheus/lib/mixin.libsonnet');
local certManagerMixin = addMixin({
  name: 'cert-manager',
  mixin: (import 'cert-manager-mixin/mixin.libsonnet'),
});

{
  values+: {
    prometheus+: {
      podAntiAffinity: 'hard',
    },
    grafana+: {
      config+: {
        sections+: {
          server+: {
            root_url: 'https://grafana.' + $.values.common.baseDomain,
          },
          date_formats+: {
            default_timezone: 'Europe/Warsaw',
          },
        },
      },
      dashboards+: certManagerMixin.grafanaDashboards,
    },
    ntfyReceiver+: {
      namespace: $.values.common.namespace,
      version: '0.4.0',
      image: 'xenrox/ntfy-alertmanager:' + self.version,
    },
    alertmanager+: {
      secrets+: [$.alertmanager.receiversSecret.metadata.name],
      config+: {
        route+: {
          group_by: ['namespace', 'job'],
          receiver: 'ntfy',
          routes: [
            {
              matchers: ['alertname = Watchdog'],
              receiver: 'healthchecks.io',
              repeat_interval: '2m',
              group_interval: '2m',
            },
            {
              matchers: ['alertname = InfoInhibitor'],
              receiver: 'null',
            },
          ],
        },
        receivers: [
          {
            name: 'ntfy',
            webhook_configs: [{
              url: 'http://' + $.ntfyReceiver.service.metadata.name + '.' + $.ntfyReceiver.service.metadata.namespace + '.svc:' + $.ntfyReceiver.service.spec.ports[0].port,
            }],
          },
          {
            name: 'healthchecks.io',
            webhook_configs: [{
              send_resolved: false,
              url_file: '/etc/alertmanager/secrets/' + $.alertmanager.receiversSecret.metadata.name + '/healthchecks-io-url',
            }],
          },
          {
            name: 'null',
          },
        ],
      },
    },
  },

  kubePrometheus+: {
    namespace+: {
      metadata+: {
        labels+: {
          'pod-security.kubernetes.io/enforce': 'privileged',
          'pod-security.kubernetes.io/enforce-version': 'latest',
          'pod-security.kubernetes.io/audit': 'privileged',
          'pod-security.kubernetes.io/audit-version': 'latest',
          'pod-security.kubernetes.io/warn': 'privileged',
          'pod-security.kubernetes.io/warn-version': 'latest',
        },
      },
    },
  },

  other: {
    certManagerPrometheusRules: certManagerMixin.prometheusRules,
  },
}
