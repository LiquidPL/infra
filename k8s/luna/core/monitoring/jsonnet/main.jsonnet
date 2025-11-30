local ntfyReceiver = (import 'common/ntfy-receiver.libsonnet');

local kp =
  (import 'kube-prometheus/main.libsonnet') +
  (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  (import 'common/defaults.libsonnet') +
  (import 'common/tolerations.libsonnet') +
  {
    values+: {
      common+: {
        namespace: 'monitoring',
        baseDomain: 'luna.liquid.sh',
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
      prometheusOperator+: {
        configReloaderResources: {
          requests: { cpu: '10m', memory: '50Mi' },
          limits: { cpu: '0', memory: '50Mi' },
        },
      },
      prometheus+: {
        resources: {
          requests: { cpu: '100m', memory: '1024Mi' },
          limits: { memory: '1024Mi' },
        },
        namespaces: [
          'default',
          'kube-system',
          'cert-manager',
        ],
        externalLabels: { cluster: 'luna' },
      },
    },

    kubernetesControlPlane+: {
      // k3s exposes all this data under single endpoint and those can be obtained via "kubelet" Service
      serviceMonitorApiserver:: null,
      serviceMonitorKubeControllerManager:: null,
      serviceMonitorKubeScheduler:: null,
      podMonitorKubeProxy:: null,
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
                storageClassName: 'local-path',
                accessModes: ['ReadWriteOnce'],
                resources: { requests: { storage: '5Gi' } },
              },
            },
          },
        },
      },
    },

    grafana:: super.grafana, # disable grafana as it's handled by homelab

    ntfyReceiver: ntfyReceiver($.values.ntfyReceiver) + {
      secret: (import 'resources/ntfy-receiver/secret.json'),
    },

    alertmanager+: {
      receiversSecret: (import 'resources/alertmanager/receivers-secret.json'),
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
