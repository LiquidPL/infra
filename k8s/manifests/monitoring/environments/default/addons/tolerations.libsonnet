local controlPlaneToleration() = {
  key: 'node-role.kubernetes.io/control-plane',
  operator: 'Exists',
  effect: 'NoSchedule',
};

{
  prometheus+:: {
    prometheus+: {
      spec+: {
        tolerations: [controlPlaneToleration()],
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
