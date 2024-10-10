local controlPlaneToleration() = {
  key: 'node-role.kubernetes.io/control-plane',
  operator: 'Exists',
  effect: 'NoSchedule',
};

{
  prometheus+:: {
    prometheus+: {
      spec+: {
        tolerations: [
          {
            key: 'cpu-class',
            operator: 'Equal',
            value: 'low-performance',
            effect: 'NoSchedule',
          }
        ],
      },
    },
  },
  alertmanager+:: {
    alertmanager+: {
      spec+: {
        tolerations: [controlPlaneToleration()],
      },
    },
  },
}
