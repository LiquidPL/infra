#!/bin/bash

set -ouex pipefail

ARCH="$(rpm -E '%_arch')"
KERNEL="$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
RELEASE="$(rpm -E '%fedora')"

dnf5 -y install dnf5-plugins

dnf5 -y copr enable liquidpl/gasket
dnf versionlock add -y kernel-${KERNEL} \
                       kernel-core-${KERNEL} \
                       kernel-devel-${KERNEL} \
                       kernel-devel-matched-${KERNEL} \
                       kernel-modules-${KERNEL} \
                       kernel-modules-core-${KERNEL} \
                       kernel-modules-extra-${KERNEL} \
                       kernel-uki-virt-${KERNEL}

dnf5 -y install akmod-gasket

akmods --force --kernels ${KERNEL} --kmod gasket
modinfo /usr/lib/modules/${KERNEL}/extra/gasket/{gasket,apex}.ko.xz > /dev/null \
|| (find /var/cache/akmods/gasket/ -name \*.log -print -exec cat {} \; && exit 1)

cp /var/cache/akmods/gasket/*.rpm /kmods
