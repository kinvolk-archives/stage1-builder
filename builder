#!/bin/bash

test -n "${DEBUG}" && set -x || DEBUG=
set -eu
set -o pipefail

readonly dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# load default config
# shellcheck source=/dev/null
source "${dir}/builder-config"

readonly user_config_file="${dir}/.config"

# load custom config if available
# shellcheck source=/dev/null
test -f "${user_config_file}" && source "${user_config_file}"

readonly kernel_version="${S1B_KERNEL_VERSION}"
readonly kernel_version_suffix="${S1B_KERNEL_VERSION_SUFFIX}"
if [[ "${kernel_version}" =~ ^.*-rc[0-9]+$ ]]; then
  readonly kernel_version_minor="${kernel_version%-rc*}"
else
  readonly kernel_version_minor="${kernel_version%.*}"
fi

readonly aci_dir="${S1B_ACI_DIR}"
mkdir -p "${aci_dir}"

readonly out_dir="${S1B_OUT_DIR}"
mkdir -p "${out_dir}"

readonly target_aci="${out_dir}/stage1-kvm-${S1B_UPSTREAM_STAGE1_KVM_VERSION}-linux-${kernel_version}.aci"

readonly rootfs_dir="${aci_dir}/rootfs"
mkdir -p "${rootfs_dir}"

readonly build_dir="${S1B_BUILD_DIR}"
mkdir -p "${build_dir}"

if [[ "${kernel_version}" =~ ^.*-rc[0-9]+$ ]]; then
  readonly kernel_url="https://cdn.kernel.org/pub/linux/kernel/v4.x/testing/linux-${kernel_version}.tar.xz"
else
  readonly kernel_url="https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${kernel_version}.tar.xz"
fi
readonly kernel_dir="${build_dir}/kernel"
mkdir -p "${kernel_dir}"
readonly kernel_source_dir="${kernel_dir}/source"
mkdir -p "${kernel_source_dir}"
readonly kernel_bzimage="${kernel_source_dir}/arch/x86/boot/bzImage"
readonly kernel_reboot_patch_url="https://raw.githubusercontent.com/coreos/rkt/v1.26.0/stage1/usr_from_kvm/kernel/patches/0001-reboot.patch"
readonly kernel_api_header_dir="/lib/modules/${kernel_version}${kernel_version_suffix}"
readonly kernel_header_dir="/lib/modules/${kernel_version}${kernel_version_suffix}/source"

readonly busybox_mkdir_url="https://busybox.net/downloads/binaries/1.26.2-i686/busybox_MKDIR"

readonly mk="$(which make) -j${S1B_JOBS}"

kernel_config="${dir}/config/linux-${kernel_version}.config"
if [[ ! -f "${kernel_config}" ]]; then
  kernel_config="${dir}/config/linux-${kernel_version_minor}.config"
  if [[ ! -f "${kernel_config}" ]]; then
    echo "couldn't find config for kernel ${kernel_version} or ${kernel_version_minor} in ${dir}/config - aborting" >&2
    exit 1
  fi
fi

# stage1 aci already build?
test -f "${target_aci}" && {
  echo "${target_aci} exists already, nothing to do" >&2
  exit 0
}

# download kernel
test -f "${kernel_dir}/kernel.tar.xz" || curl -LsS "${kernel_url}" -o "${kernel_dir}/kernel.tar.xz"

# unpack kernel
test "$(find "${kernel_source_dir}" -maxdepth 0 -type d -empty 2>/dev/null)" && tar -C "${kernel_source_dir}" --strip-components=1 -xf "${kernel_dir}/kernel.tar.xz"

# configure kernel
test -f "${kernel_source_dir}/.config" || sed -e "s/-rkt-v1/${kernel_version_suffix}/g" "${kernel_config}" >"${kernel_source_dir}/.config"

# build kernel
test -f "${kernel_bzimage}" ||
(
  cd "${kernel_source_dir}"
  curl -LsS "${kernel_reboot_patch_url}" -O
  # TODO(schu) fails when patch was applied already
  patch --silent -p1 < $(basename "${kernel_reboot_patch_url}")
  for patch_url in ${S1B_EXTRA_KERNEL_PATCH_URLS} ; do
    curl -LsS "${patch_url}" -O
    patch --silent -p1 < $(basename "${patch_url}")
  done
  for patch_file in ${S1B_EXTRA_KERNEL_PATCH_FILES} ; do
    patch --silent -p1 < "${patch_file}"
  done
  ${mk} bzImage
)

# import kernel
rsync -a "${kernel_bzimage}" "${rootfs_dir}/bzImage"

# import kernel header
mkdir -p "${rootfs_dir}/${kernel_header_dir}/include/arch/x86/include"
(
  cd "${kernel_source_dir}"

  # install kernel api header
  ${mk} headers_install INSTALL_HDR_PATH="${rootfs_dir}/${kernel_api_header_dir}" >/dev/null

  # loosely following arch for the copied kernel headers
  # https://git.archlinux.org/svntogit/packages.git/tree/trunk/PKGBUILD?h=packages/linux#n158

  for i in acpi asm-generic config crypto drm generated keys linux math-emu \
    media net pcmcia scsi soc sound trace uapi video xen; do
    rsync -a "include/${i}" "${rootfs_dir}/${kernel_header_dir}/include/"
  done

  rsync -a "arch/x86/include/"  "${rootfs_dir}/${kernel_header_dir}/include/arch/x86/include/"
)

find "${rootfs_dir}/${kernel_header_dir}" \( -name '.install' -or -name '..install.cmd' \) -delete

# add busybox mkdir to stage1
mkdir -p "${rootfs_dir}/usr/bin"
test -f "${rootfs_dir}/usr/bin/mkdir" ||
(
  cd "${rootfs_dir}/usr/bin"
  curl -LsS "${busybox_mkdir_url}" -o "mkdir"
  chmod +x "mkdir"
)

# add systemd drop-in to bind mount kernel headers
mkdir -p "${rootfs_dir}/etc/systemd/system/prepare-app@.service.d"
cat <<EOF >"${rootfs_dir}/etc/systemd/system/prepare-app@.service.d/10-bind-mount-kernel-header.conf"
[Service]
ExecStartPost=/usr/bin/mkdir -p %I/${kernel_api_header_dir}
ExecStartPost=/usr/bin/mount --bind "${kernel_api_header_dir}" %I/${kernel_api_header_dir}
EOF

# include manifest
sed \
  -e "s/{{kernel_version}}/${kernel_version}/g" \
  -e "s/{{upstream_stage1_kvm_version}}/${S1B_UPSTREAM_STAGE1_KVM_VERSION}/g" \
  "${dir}/manifest.tmpl.json" >"${aci_dir}/manifest"

# build aci
actool build --overwrite --no-compression "${aci_dir}" "${target_aci}"
readonly hashsum=$(sha512sum "${target_aci}" | awk '{print $1}')
gzip -cf "${target_aci}" >"${target_aci}.gz"
mv "${target_aci}.gz" "${target_aci}"

echo "Successfully build ${target_aci} with id sha512-${hashsum}"
