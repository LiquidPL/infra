# Patched images for [`democratic-csi`](https://github.com/democratic-csi/democratic-csi)

The `Containerfile` in this repository builds a patched version of [`democratic-csi`](https://github.com/democratic-csi/democratic-csi), adding a way to configure the driver using environment variables (pull request [pending](https://github.com/democratic-csi/democratic-csi/pull/401)).

The images are published on the [GitHub Container Registry](https://github.com/LiquidPL/infra/pkgs/container/democratic-csi). Currently, there's only `linux/amd64` and `linux/arm64` images, please let me know via an issue if you want builds for a different platform/arch, or if you need a newer version built.
