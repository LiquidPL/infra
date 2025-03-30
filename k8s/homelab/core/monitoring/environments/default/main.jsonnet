local ingress(metadata, host, service) = {
  apiVersion: 'networking.k8s.io/v1',
  kind: 'Ingress',
  metadata: metadata + {
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
              }
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

local allowIngressNetworkPolicy(port) = {
  spec+: {
    ingress+: [
      {
        from: [
          {
            namespaceSelector: {
              matchLabels: {
                'kubernetes.io/metadata.name': 'network',
              }
            },
            podSelector: {
              matchLabels: {
                'app.kubernetes.io/name': 'traefik',
              },
            },
          },
        ],
        ports: [
          {
            port: port,
            protocol: 'TCP',
          },
        ],
      },
    ],
  },
};

local kp =
  (import 'kube-prometheus/main.libsonnet') +
  (import 'addons/tolerations.libsonnet') +
  (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  {
    values+:: {
      common+: {
        namespace: 'monitoring',
        baseDomain: 'hs.liquid.sh',
      },
      kubernetesControlPlane+: {
        kubeProxy: true,
        mixin+: {
          _config+: {
            // k3s exposes all this data under single endpoint and those can be obtained via "kubelet" Service
            kubeSchedulerSelector: 'job="kubelet"',
            kubeControllerManagerSelector: 'job="kubelet"',
            kubeApiserverSelector: 'job="kubelet"',
            kubeProxySelector: 'job="kubelet"',
          },
        },
      },
      prometheus+: {
        replicas: 1,
        resources: {
          requests: { cpu: '100m', memory: '1024Mi' },
          limits: { memory: '2048Mi' },
        },
        namespaces: ['default', 'kube-system', 'monitoring', 'navidrome'],
      },
      grafana+: {
        sections+: {
          server+: {
            root_url: 'https://grafana.' + $.values.common.baseDomain,
          },
        },
      },
    },
    prometheus+:: {
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
    grafana+:: {
      deployment+: {
        spec+: {
          template+: {
            spec+: {
              index:: [
                x for x in std.range(0, std.length(super.volumes) - 1)
                if super.volumes[x].name == "grafana-storage" != []
              ][0],
              volumes: super.volumes[0:self.index] + [{ name: 'grafana-storage', persistentVolumeClaim: { claimName: $.grafana.pvc.metadata.name } }] + super.volumes[self.index + 1:]
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
          resources: { requests: { storage: '60Mi' } }
        },
      },

      networkPolicy+: allowIngressNetworkPolicy($.grafana.service.spec.ports[0].port),
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
    kubernetesControlPlane+: {
      // k3s exposes all this data under single endpoint and those can be obtained via "kubelet" Service
      serviceMonitorApiserver:: null,
      serviceMonitorKubeControllerManager:: null,
      serviceMonitorKubeScheduler:: null,
      podMonitorKubeProxy:: null,
    },
  };

local manifests =
  [kp.kubePrometheus[name] for name in std.objectFields(kp.kubePrometheus)] +
  [kp.prometheusOperator[name] for name in std.objectFields(kp.prometheusOperator)] +
  [kp.alertmanager[name] for name in std.objectFields(kp.alertmanager)] +
  [kp.blackboxExporter[name] for name in std.objectFields(kp.blackboxExporter)] +
  [kp.grafana[name] for name in std.objectFields(kp.grafana)] +
  // [ kp.pyrra[name] for name in std.objectFields(kp.pyrra)] +
  [kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics)] +
  [kp.kubernetesControlPlane[name] for name in std.objectFields(kp.kubernetesControlPlane)] +
  [kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter)] +
  [kp.prometheus[name] for name in std.objectFields(kp.prometheus)] +
  [kp.prometheusAdapter[name] for name in std.objectFields(kp.prometheusAdapter)];

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

// Add argo-cd annotations to all the manifests
[
  if std.endsWith(manifest.kind, 'List') && std.objectHas(manifest, 'items')
  then manifest { items: [argoAnnotations(item) for item in manifest.items] }
  else argoAnnotations(manifest)
  for manifest in manifests
]
