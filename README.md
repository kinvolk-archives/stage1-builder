# stage1-builder

Experimental build script for custom rkt stage1-kvm images.

stage1-builder relies on [ACI dependencies](https://github.com/appc/spec/blob/master/spec/aci.md).
This allows us to base our images on the upstream stage1-kvm and only
update the kernel.

## Usage

```
./builder
```

builds a stage1-kvm with the Linux kernel as configured in `builder-config`
(usually the latest stable).  To build a different version, use the
`S1B_KERNEL_VERSION` var, e.g.

```
S1B_KERNEL_VERSION=4.4.45 ./builder
```

Right now kernel versions 4.9.x and 4.4.x are supported. Supporting more
kernel releases is a matter of adding a (manually prepared) config file in
`config/`.

`builder-config` contains more variables which can be used to configure
stage1-builder. Environment variables or a local file `.config` can be
used to overwrite the defaults.

stage1 provides the kernel header through a bind mount; those can be
found under

* `/lib/modules/$(uname -r)/include` for the kernel API headers
* `/lib/modules/$(uname -r)/source/include` for the kernel headers

Note: at the time of writing, you have to pre-fetch all stage1 dependencies
manually due to https://github.com/coreos/rkt/issues/2241
This is can be done as follows (the version must match
`S1B_UPSTREAM_STAGE1_KVM_VERSION` as set for the build):

```
rkt image fetch --insecure-options=image coreos.com/rkt/stage1-kvm:1.23.0
```

Our builds can be fetched from `kinvolk.io/aci/rkt/stage1-kvm`, e.g.

```
rkt image fetch --insecure-options=image kinvolk.io/aci/rkt/stage1-kvm:1.23.0,kernelversion=4.9.6
```

## Usage on Semaphore CI

As Semaphore CI doesn't include rkt by default on their platform, rkt must be
downloaded as a first step.

Example `semaphore.sh`:

```bash
#!/bin/bash

readonly rkt_version="1.23.0"

if [[ ! -f "./rkt/rkt" ]] || \
  [[ ! "$(./rkt/rkt version | awk '/rkt Version/{print $3}')" == "${rkt_version}" ]]; then

  curl -LsS "https://github.com/coreos/rkt/releases/download/v${rkt_version}/rkt-v${rkt_version}.tar.gz" \
    -o rkt.tgz

  mkdir -p rkt
  tar -xf rkt.tgz -C rkt --strip-components=1
fi

# Pre-fetch stage1 dependency due to rkt#2241
# https://github.com/coreos/rkt/issues/2241
sudo ./rkt/rkt image fetch --insecure-options=image coreos.com/rkt/stage1-kvm:${rkt_version}

sudo ./rkt/rkt run \
  --stage1-name="kinvolk.io/aci/rkt/stage1-kvm:${rkt_version},kernelversion=4.9.6" \
  --environment=C_INCLUDE_PATH="/lib/modules/4.9.6-kinvolk-v1/include" \
  ...
```
