#!/bin/bash

function fetch_ubuntu {
  local DIRNAME="ubuntu"
  local SUFFIX="amd64"
  local urlbase="http://archive.ubuntu.com"
  local images=( maverick natty oneiric precise )
  local files=( initrd.gz linux )

  mkdir ${DIRNAME}

  pushd ${DIRNAME}
  for image in ${images[@]}; do
      echo "Grabbing files for Ubuntu-${image}"
      mkdir "${image}-${SUFFIX}";
      # cp preseed.txt ../../../templates/preseed/${image}-${SUFFIX}-preseed.txt;
      for file in ${files[@]}; do
          wget "${urlbase}/ubuntu/dists/${image}/main/installer-${SUFFIX}/current/images/netboot/ubuntu-installer/${SUFFIX}/${file}" -q -P ${image}-${SUFFIX};
      done;
  done;
  popd
}

function fetch_centos {
  local DIRNAME="centos"
  local SUFFIX="x86_64"
  local urlbase="http://mirror.centos.org"
  local images=( 6.4 )
  local files=( initrd.img vmlinuz )

  mkdir ${DIRNAME}

  pushd ${DIRNAME}
  for image in ${images[@]}; do
      echo "Grabbing files for CentOS-${image}"
      mkdir "${image}-${SUFFIX}";
      for file in ${files[@]}; do
          wget "${urlbase}/centos/${image}/os/${SUFFIX}/images/pxeboot/${file}" -q -P ${image}-${SUFFIX};
      done;
  done;
  popd
}

# I should also be made into a manage.py command
OLDPWD="$PWD"
cd "$(dirname $0)"

echo "Downloading syslinux 6.01"
wget https://www.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.01.tar.bz2 -qO- | tar xj

cd local/tftproot
for s in core/pxelinux.0 com32/menu/menu.c32 com32/mboot/mboot.c32 com32/chain/chain.c32 \
                         com32/elflink/ldlinux/ldlinux.c32 com32/libutil/libutil.c32 \
                         com32/lib/libcom32.c32; do
    ln -s "../../syslinux-6.0.1/bios/${s}"
done

fetch_ubuntu
fetch_centos

cd $OLDPWD
