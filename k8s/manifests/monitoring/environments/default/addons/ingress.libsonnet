{
  values+:: {
    grafana+:: {
      sections+: {
        server+: {
          root_url: 'https://grafana.hs.liquid.sh',
        },
      },
    },
  },
  ingress+:: {
    grafana: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: {
        name: 'grafana',
        namespace: $.values.common.namespace,
        annotations: {
          'cert-manager.io/cluster-issuer': 'letsencrypt'
        },
      },
      spec: {
        rules: [
          {
            host: 'grafana.hs.liquid.sh',
            http: {
              paths: [
                {
                  pathType: 'Prefix',
                  path: '/',
                  backend: {
                    service: {
                      name: $.grafana.service.metadata.name,
                      port: {
                        name: $.grafana.service.spec.ports[0].name,
                      },
                    },
                  },
                },
              ],
            },
          }
        ],
        tls: [
          {
            hosts: ['grafana.hs.liquid.sh'],
            secretName: 'tls-grafana',
          },
        ],
      },
    },
  },
  grafana+:: {
    networkPolicy+: {
      spec+: {
        ingress: [
          super.ingress[0] + {
            from+: [
              {
                namespaceSelector: {
                  matchLabels: {
                    'kubernetes.io/metadata.name': 'network',
                  },
                },
                podSelector: {
                  matchLabels: {
                    'app.kubernetes.io/name': 'traefik',
                  },
                },
              },
            ],
          },
        ] + super.ingress[1:],
      },
    },
  },
}
