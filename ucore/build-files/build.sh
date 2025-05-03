#!/bin/bash

set -ouex pipefail

RELEASE="$(rpm -E '%fedora')"

curl -o /etc/yum.repos.d/_copr-gasket.repo https://copr.fedorainfracloud.org/coprs/liquidpl/gasket/repo/fedora-${RELEASE}/liquidpl-gasket-fedora-${RELEASE}.repo
cp /ctx/rancher-k3s-common.repo /etc/yum.repos.d/

rpm-ostree install -y /ctx/built-kmods/*.rpm \
    k3s-selinux \
    htop \
    iotop

rm /etc/yum.repos.d/_copr-gasket.repo \
   /etc/yum.repos.d/rancher-k3s-common.repo

# TODO: remove this once bootc-image-builder is updated
# to work with rpm-ostree based distros
# see: https://github.com/ublue-os/image-template/issues/60
if [[ ! -d /usr/libexec/rpm-ostree/wrapped ]]; then
    echo "cliwrap is not setup, skipping..."
    exit 0
fi

# Remove wrapped binaries
rm -f \
    /usr/bin/yum \
    /usr/bin/dnf \
    /usr/bin/kernel-install

# binaries which were wrapped
mv -f /usr/libexec/rpm-ostree/wrapped/* /usr/bin
rm -rf /usr/libexec/rpm-ostree

# Install dnf5 if not present
if [[ "$(rpm -E %fedora)" -lt 41 ]]; then
    rpm-ostree install --idempotent dnf5
    if [[ ! "${IMAGE}" =~ ucore ]]; then
        dnf5 install -y dnf5-plugins
    fi
fi
