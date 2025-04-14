local defaults = {
  local defaults = self,
  name: 'ntfy-receiver',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    requests: { cpu: '2m', memory: '20Mi' },
    limits: { memory: '50Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'alertmanager-webhook-receiver',
    'app.kubernetes.io/part-of': 'kube-prometheus',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  replicas: 1,
  authSecretName: 'ntfy-receiver-auth',
};

function(params) {
  _config:: defaults + params,
  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },
  assert std.isObject($._config.resources),

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $._metadata,
    spec: {
      ports: [{
        name: 'http',
        targetPort: $.deployment.spec.template.spec.containers[0].ports[0].name,
        port: 8080,
      }],
      selector: $._config.selectorLabels,
    },
  },

  networkPolicy: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: $._metadata,
    spec: {
      podSelector: {
        matchLabels: $._config.selectorLabels,
      },
      policyTypes: ['Egress', 'Ingress'],
      ingress: [{
        from: [{
          podSelector: {
            matchLabels: {
              'app.kubernetes.io/name': 'alertmanager',
              'app.kubernetes.io/part-of': 'kube-prometheus',
            },
          },
        }],
        ports: [{
          port: $.service.spec.ports[0].port,
          protocol: 'TCP',
        }],
      }],
      egress: [
        {
          to: [{
            ipBlock: {
              cidr: '128.140.29.17/32',  // IP address of load balancer that provides access to ntfy
            },
          }],
          ports: [{
            port: 443,
            protocol: 'TCP',
          }],
        },
        {
          to: [{
            namespaceSelector: {
              matchLabels: {
                'kubernetes.io/metadata.name': 'kube-system',
              },
            },
          }],
          ports: [
            { port: 53, protocol: 'UDP' },
            { port: 53, protocol: 'TCP' },
          ],
        },
      ],
    },
  },

  secret: (import 'ntfy-receiver/secret.json'),

  configMap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: $._metadata {
      name: $._config.name + '-config',
    },
    data: {
      config: (importstr 'ntfy-receiver/config'),
    },
  },

  deployment: {
    local receiver = {
      name: $._config.name,
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      securityContext: {
        allowPrivilegeEscalation: false,
        readOnlyRootFilesystem: true,
        capabilities: { drop: ['ALL'] },
      },
      ports: [{
        name: 'http',
        containerPort: 8080,
        protocol: 'TCP',
      }],
      resources: $._config.resources,
      local probe = {
        tcpSocket: {
          port: 'http',
        },
      },
      livenessProbe: probe,
      readinessProbe: probe,
      volumeMounts: [
        {
          name: 'config',
          mountPath: '/etc/ntfy-alertmanager',
          readOnly: true,
        },
        {
          name: 'auth',
          mountPath: '/etc/ntfy-alertmanager/secrets',
          readOnly: true,
        },
      ],
    },

    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: $._metadata,
    spec: {
      replicas: $._config.replicas,
      selector: { matchLabels: $._config.selectorLabels },
      template: {
        metadata: {
          labels: $._config.commonLabels,
        },
        spec: {
          restartPolicy: 'Always',
          securityContext: {
            runAsUser: 1000,
            runAsGroup: 1000,
            runAsNonRoot: true,
          },
          containers: [receiver],
          volumes: [
            {
              name: 'config',
              configMap: {
                name: $.configMap.metadata.name,
              },
            },
            {
              name: 'auth',
              secret: {
                secretName: $._config.authSecretName,
              },
            },
          ],
        },
      },
    },
  },
}
