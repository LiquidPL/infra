{
  apiVersion: 'storage.k8s.io/v1',
  kind: 'StorageClass',
  metadata: {
    name: 'longhorn-prometheus',
  },
  provisioner: 'driver.longhorn.io',
  allowVolumeExpansion: true,
  reclaimPolicy: 'Retain',
  parameters: {
    numberOfReplicas: '1',
    dataLocality: 'best-effort',
    staleReplicaTimeout: '30',
    fromBackup: '',
    fsType: 'ext4',
  },
}
