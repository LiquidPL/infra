#!/bin/bash

set -ouex pipefail

RELEASE="$(rpm -E '%fedora')"

curl -o /etc/yum.repos.d/_copr-gasket.repo https://copr.fedorainfracloud.org/coprs/liquidpl/gasket/repo/fedora-${RELEASE}/liquidpl-gasket-fedora-${RELEASE}.repo

rpm-ostree install -y /ctx/built-kmods/*.rpm

rm /etc/yum.repos.d/_copr-gasket.repo
