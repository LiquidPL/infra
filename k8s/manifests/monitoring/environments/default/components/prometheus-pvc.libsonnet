{
  apiVersion: 'v1',
  kind: 'PersistentVolumeClaim',
  spec: {
    storageClassName: 'longhorn-prometheus',
    accessModes: ['ReadWriteOnce'],
    resources: { requests: { storage: '20Gi' } },
  },
}
