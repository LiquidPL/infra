#!/bin/bash

set -ouex pipefail

mkdir -p kmods/

podman run -it --rm \
    -v ./build-files/kmods/:/ctx \
    -v ./kmods:/kmods \
    ghcr.io/ublue-os/ucore-minimal:stable \
    /bin/bash -c "/ctx/build-kmod-gasket.sh"
