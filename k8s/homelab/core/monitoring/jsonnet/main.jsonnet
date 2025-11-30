local httpRoute(metadata, host, backendRef) = {
  apiVersion: 'gateway.networking.k8s.io/v1',
  kind: 'HTTPRoute',
  metadata: metadata,
  spec: {
    parentRefs: [
      { namespace: 'envoy-gateway-system', name: 'gateway-local' },
      { namespace: 'envoy-gateway-system', name: 'gateway-tailscale' },
    ],
    hostnames: [host],
    rules: [{
      matches: [{ path: { type: 'PathPrefix', value: '/' } }],
      backendRefs: [backendRef],
    }],
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
                'kubernetes.io/metadata.name': 'envoy-gateway-system',
              },
            },
            podSelector: {
              matchLabels: {
                'app.kubernetes.io/component': 'proxy',
                'app.kubernetes.io/name': 'envoy',
                'app.kubernetes.io/managed-by': 'envoy-gateway',
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

local ntfyReceiver = (import 'common/ntfy-receiver.libsonnet');
local kubeletMetricsForwarder = (import 'lib/kubelet-metrics-forwarder.libsonnet');

local kp =
  (import 'kube-prometheus/main.libsonnet') +
  (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  (import 'common/defaults.libsonnet') +
  (import 'common/tolerations.libsonnet') +
  (import 'lib/grafana-oauth.libsonnet') +
  {
    values+: {
      common+: {
        platform: 'kubespray',
        namespace: 'monitoring',
        baseDomain: 'hs.liquid.sh',
      },
      prometheusOperator+: {
        configReloaderResources: {
          requests: { cpu: '10m', memory: '50Mi' },
          limits: { cpu: '0', memory: '50Mi' },
        },
      },
      prometheus+: {
        podAntiAffinity: 'hard',
        resources: {
          requests: { cpu: '100m', memory: '1024Mi' },
          limits: { memory: '2048Mi' },
        },
        namespaces: [
          'default',
          'kube-system',
          'cert-manager',
          'monitoring',
          'navidrome',
          'frigate',
          'immich',
          'authentik',
        ],
        externalLabels: { cluster: 'homelab' },
      },
      grafana+: {
        dashboards+: {
          'navidrome.json': (import 'resources/dashboards/navidrome.json'),
        },
      },
      kubeletMetricsForwarder+: {
        namespace: 'kube-system',
        image: 'alpine/socat:1.8.0.3@sha256:67f2f93884c21216776aeeb1bc5326d8302f80e585e13ee1e0a6d8bb08e45436',
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
                storageClassName: 'topolvm-provisioner',
                accessModes: ['ReadWriteOnce'],
                resources: { requests: { storage: '20Gi' } },
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
          storageClassName: 'longhorn',
          accessModes: ['ReadWriteOnce'],
          resources: { requests: { storage: '60Mi' } },
        },
      },

      httpRoute: httpRoute(
        $.grafana.service.metadata,
        'grafana.' + $.values.common.baseDomain,
        {
          group: '',
          kind: 'Service',
          namespace: $.grafana.service.metadata.namespace,
          name: $.grafana.service.metadata.name,
          port: $.grafana.service.spec.ports[0].port,
        }
      ),
      networkPolicy+: allowIngressNetworkPolicy($.grafana.service.spec.ports[0].port),
    },

    ntfyReceiver: ntfyReceiver($.values.ntfyReceiver) + {
      secret: (import 'resources/ntfy-receiver/secret.json'),
    },
    kubeletMetricsForwarder: kubeletMetricsForwarder($.values.kubeletMetricsForwarder),

    alertmanager+: {
      receiversSecret: (import 'resources/alertmanager/receivers-secret.json'),
      httpRoute: httpRoute(
        $.alertmanager.service.metadata,
        'alertmanager.' + $.values.common.baseDomain,
        {
          group: '',
          kind: 'Service',
          namespace: $.alertmanager.service.metadata.namespace,
          name: $.alertmanager.service.metadata.name,
          port: $.alertmanager.service.spec.ports[0].port,
        }
      ),
      securityPolicy: {
        apiVersion: 'gateway.envoyproxy.io/v1alpha1',
        kind: 'SecurityPolicy',
        metadata: { name: 'forward-auth' },
        spec: {
          targetRefs: [{
              group: 'gateway.networking.k8s.io',
              kind: 'HTTPRoute',
              name: $.alertmanager.httpRoute.metadata.name
            }],
          extAuth: {
            headersToExtAuth: ['cookie'],
            http: {
              backendRefs: [{
                kind: 'Service',
                name: 'ak-outpost-homelab',
                namespace: 'authentik',
                port: 9000,
              }],
              path: '/outpost.goauthentik.io/auth/envoy',
              headersToBackend: ['set-cookie'],
            },
          },
        },
      },
      networkPolicy+: allowIngressNetworkPolicy($.alertmanager.service.spec.ports[0].port),
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
