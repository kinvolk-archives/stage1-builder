#!/bin/bash

test -n "${DEBUG}" && set -x || DEBUG=
set -eu
set -o pipefail

if [[ $# -gt 3 ]]; then
  echo "Usage: $0 <kernel version> [<target dir> [<build dir>]]" >&2
  echo "Example: $0 4.9.4 aci/ /tmp/aci-build"
  exit 1
fi

readonly dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly kernel_version="${1:-4.9.4}"
readonly aci_dir="${2:-${dir}/aci/${kernel_version}}"
mkdir -p "${aci_dir}"
readonly target_aci="stage1-kvm-linux-${kernel_version}.aci"
readonly rootfs_dir="${aci_dir}/rootfs"
mkdir -p "${rootfs_dir}"
readonly build_dir="${3:-${dir}/build/${kernel_version}}"
mkdir -p "${build_dir}"
readonly kernel_url="https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${kernel_version}.tar.xz"
readonly kernel_dir="${build_dir}/kernel"
mkdir -p "${kernel_dir}"
readonly kernel_source_dir="${kernel_dir}/source"
mkdir -p "${kernel_source_dir}"
readonly kernel_config_url="https://raw.githubusercontent.com/coreos/rkt/a208528aa583e50664326c841b1d9b53d8b42c21/stage1/usr_from_kvm/kernel/cutdown-config"
readonly kernel_bzimage="${kernel_source_dir}/arch/x86/boot/bzImage"
readonly kernel_reboot_patch_url="https://raw.githubusercontent.com/coreos/rkt/v1.22.0/stage1/usr_from_kvm/kernel/patches/0001-reboot.patch"

test -f "${kernel_dir}/kernel.tar.xz" || curl -LsS "${kernel_url}" -o "${kernel_dir}/kernel.tar.xz"

test $(find "${kernel_source_dir}" -maxdepth 0 -type d -empty 2>/dev/null) && tar -C "${kernel_source_dir}" --strip-components=1 -xf "${kernel_dir}/kernel.tar.xz"

test -f "${kernel_source_dir}/.config" || curl -LsS "${kernel_config_url}" -o "${kernel_source_dir}/.config"
sed -i 's/rkt-v1/kinvolk-v1/g' "${kernel_source_dir}/.config"

test -f "${kernel_bzimage}" || (
  cd "${kernel_source_dir}"
  curl -LsS "${kernel_reboot_patch_url}" -O
  patch --silent -p1 < *.patch
  make bzImage
)

rsync -a "${kernel_bzimage}" "${rootfs_dir}/bzImage"
sed -e "s/{{kernel_version}}/${kernel_version}/" "${dir}/manifest.tmpl.json" >"${aci_dir}/manifest"
tar -czf "${target_aci}" -C "${aci_dir}" .
echo "Successfully build ${target_aci}"
