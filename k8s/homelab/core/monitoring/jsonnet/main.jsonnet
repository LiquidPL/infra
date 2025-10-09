local ingress(metadata, host, service) = {
  apiVersion: 'networking.k8s.io/v1',
  kind: 'Ingress',
  metadata: metadata {
    annotations+: {
      'cert-manager.io/cluster-issuer': 'letsencrypt',
    },
  },
  spec: {
    rules: [
      {
        host: host,
        http: {
          paths: [
            {
              pathType: 'Prefix',
              path: '/',
              backend: {
                service: service,
              },
            },
          ],
        },
      },
    ],
    tls: [
      {
        hosts: [host],
        secretName: 'tls-' + metadata.name,
      },
    ],
  },
};

local ntfyReceiver = (import 'lib/ntfy-receiver.libsonnet');
local kubeletMetricsForwarder = (import 'lib/kubelet-metrics-forwarder.libsonnet');

local kp =
  (import 'kube-prometheus/main.libsonnet') +
  (import 'lib/tolerations.libsonnet') +
  (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  {
    values+:: {
      common+: {
        platform: 'kubespray',
        namespace: 'monitoring',
        baseDomain: 'hs.liquid.sh',
      },
      prometheus+: {
        resources: {
          requests: { cpu: '100m', memory: '1024Mi' },
          limits: { memory: '2048Mi' },
        },
        namespaces: ['default', 'kube-system', 'monitoring', 'navidrome', 'frigate'],
      },
      grafana+: {
        sections+: {
          server+: {
            root_url: 'https://grafana.' + $.values.common.baseDomain,
          },
        },
        dashboards+: {
          'navidrome.json': (import 'dashboards/navidrome.json'),
        },
      },
      ntfyReceiver+: {
        namespace: $.values.common.namespace,
        version: '0.4.0',
        image: 'xenrox/ntfy-alertmanager:' + self.version,
      },
      kubeletMetricsForwarder+: {
        namespace: 'kube-system',
        image: 'alpine/socat:1.8.0.3@sha256:67f2f93884c21216776aeeb1bc5326d8302f80e585e13ee1e0a6d8bb08e45436',
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

    prometheus+: {
      prometheus+: {
        spec+: {
          retention: '14d',
          storage: {
            volumeClaimTemplate: {
              apiVersion: 'v1',
              kind: 'PersistentVolumeClaim',
              spec: {
                storageClassName: 'iscsi-csi',
                accessModes: ['ReadWriteOnce'],
                resources: { requests: { storage: '50Gi' } },
              },
            },
          },
        },
      },
    },

    grafana+: {
      deployment+: {
        spec+: {
          template+: {
            spec+: {
              index:: [
                x
                for x in std.range(0, std.length(super.volumes) - 1)
                if super.volumes[x].name == 'grafana-storage' != []
              ][0],
              volumes: super.volumes[0:self.index] + [{ name: 'grafana-storage', persistentVolumeClaim: { claimName: $.grafana.pvc.metadata.name } }] + super.volumes[self.index + 1:],
            },
          },
        },
      },

      pvc: {
        apiVersion: 'v1',
        kind: 'PersistentVolumeClaim',
        metadata: {
          name: 'grafana-app-data',
          namespace: $.grafana.deployment.metadata.namespace,
        },
        spec: {
          storageClassName: 'nfs-csi',
          accessModes: ['ReadWriteOnce'],
          resources: { requests: { storage: '60Mi' } },
        },
      },

      networkPolicy: {
        apiVersion: 'cilium.io/v2',
        kind: 'CiliumNetworkPolicy',
        metadata: $.grafana._metadata,
        spec: {
          endpointSelector: {
            matchLabels: $.grafana._config.selectorLabels,
          },
          ingress: [
            {
              fromEndpoints: [{ matchLabels: { 'app.kubernetes.io/name': 'prometheus' } }],
              toPorts: [{ ports: [{ port: '3000', protocol: 'TCP' }] }],
            },
            { fromEntities: ['world'] },
            {
              fromEndpoints: [{ matchExpressions: [{ key: 'reserved:ingress', operator: 'Exists' }] }],
              toPorts: [{ ports: [{ port: '3000', protocol: 'TCP' }] }],
            },
          ],
          egress: [
            { toEntities: ['all'] },
          ],
        },
      },
      ingress: ingress(
        $.grafana.service.metadata,
        'grafana.' + $.values.common.baseDomain,
        {
          name: $.grafana.service.metadata.name,
          port: {
            name: $.grafana.service.spec.ports[0].name,
          },
        },
      ),
    },

    ntfyReceiver: ntfyReceiver($.values.ntfyReceiver),
    kubeletMetricsForwarder: kubeletMetricsForwarder($.values.kubeletMetricsForwarder),

    alertmanager+: {
      receiversSecret: (import 'lib/alertmanager/receivers-secret.json'),
    },
  };

local argoAnnotations(manifest) =
  manifest {
    metadata+: {
      annotations+: {
        'argocd.argoproj.io/sync-wave':
          // Make sure to sync the Namespace, CRDs, and StorageClasses before anything else (to avoid sync failures)
          if std.member(['CustomResourceDefinition', 'Namespace', 'StorageClass'], manifest.kind)
          then '-5'
          // And sync all the roles outside of the main & kube-system last (in case some of the namespaces don't exist yet)
          else if std.objectHas(manifest, 'metadata')
                  && std.objectHas(manifest.metadata, 'namespace')
                  && !std.member([kp.values.common.namespace, 'kube-system'], manifest.metadata.namespace)
          then '10'
          else '5',
        'argocd.argoproj.io/sync-options':
          // Use replace strategy for CRDs, as they're too big fit into the last-applied-configuration annotation that kubectl apply wants to use
          if manifest.kind == 'CustomResourceDefinition' then 'Replace=true'
          else '',
      },
    },
  };

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(argoAnnotations(kp[component][resource]))  // Add argo-cd annotations to all the manifests
  for component in std.objectFields(kp)
  for resource in std.objectFields(kp[component])
}
