local controlPlaneToleration() = {
  key: 'node-role.kubernetes.io/control-plane',
  operator: 'Exists',
  effect: 'NoSchedule',
};

{
  alertmanager+: {
    alertmanager+: {
      spec+: {
        tolerations: [controlPlaneToleration()],
      },
    },
  },
}
