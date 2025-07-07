#!/bin/bash

set -ouex pipefail

rpm-ostree install -y \
    htop \
    ethtool \
    ipset \
    conntrack-tools

# TODO: consider moving this to the Ignition config once building
# disk images from bootc based CoreOS images is working
systemctl disable firewalld.service
