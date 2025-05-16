#!/bin/bash

set -ouex pipefail

RELEASE="$(rpm -E '%fedora')"

curl -o /etc/yum.repos.d/_copr-gasket.repo https://copr.fedorainfracloud.org/coprs/liquidpl/gasket/repo/fedora-${RELEASE}/liquidpl-gasket-fedora-${RELEASE}.repo
cp /ctx/rancher-k3s-common.repo /etc/yum.repos.d/

rpm-ostree install -y /ctx/built-kmods/*.rpm \
    htop \
    ethtool \
    ipset \
    conntrack-tools

rm /etc/yum.repos.d/_copr-gasket.repo \
   /etc/yum.repos.d/rancher-k3s-common.repo

# TODO: consider moving this to the Ignition config once building
# disk images from bootc based CoreOS images is working
systemctl disable firewalld.service
