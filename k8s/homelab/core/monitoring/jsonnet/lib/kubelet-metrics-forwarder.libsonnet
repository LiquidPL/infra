local defaults = {
  local defaults = self,
  name: 'kubelet-metrics-forwarder',
  namespace: error 'must provide namespace',
  image: error 'must provide image',
  resources: {
    requests: { cpu: '2m', memory: '10Mi' },
    limits: { memory: '20Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': defaults.name,
    'app.kubernetes.io/part-of': 'kube-prometheus',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
  },
};

function(params) {
  _config:: defaults + params,
  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },
  assert std.isObject($._config.resources),

  daemonSet: {
    local container = function(name, port) {
      name: name,
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      env: [{
        name: 'NODE_IP',
        valueFrom: {
          fieldRef: {
            apiVersion: 'v1',
            fieldPath: 'status.hostIP',
          },
        },
      }],
      command: ['/bin/sh'],
      args: ['-c', 'socat TCP4-LISTEN:%d,reuseaddr,bind=${NODE_IP},fork TCP4:127.0.0.1:%d' % [port, port]],
      ports: [{ containerPort: port }],
    },

    apiVersion: 'apps/v1',
    kind: 'DaemonSet',
    metadata: $._metadata,
    spec: {
      selector: { matchLabels: $._config.selectorLabels },
      template: {
        metadata: {
          labels: $._config.commonLabels,
        },
        spec: {
          nodeSelector: {
            'node-role.kubernetes.io/control-plane': '',
          },
          tolerations: [{
            key: 'node-role.kubernetes.io/control-plane',
            operator: 'Exists',
            effect: 'NoSchedule',
          }],
          hostNetwork: true,
          containers: [
            container('socat-kube-controller-manager', 10257),
            container('socat-kube-scheduler', 10259),
          ],
        },
      },
    },
  },
}
