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

A list of currently available images can be fetched from the Circle CI API, e.g.

```
curl -sSL 'https://circleci.com/api/v1.1/project/github/kinvolk/stage1-builder/latest/artifacts?branch=master&filter=successful' \
  | jq -r .[].path \
  | sed -e 's/.*\/\([^/]*\)\.aci$/\1/'
```

To verify stage1-kvm indeed boots the custom kernel, you can run `uname -r`, e.g.

```
rkt run \
  --insecure-options=image \
  --stage1-name=kinvolk.io/aci/rkt/stage1-kvm:1.23.0,kernelversion=4.9.6 \
  quay.io/coreos/alpine-sh \
  --exec=/bin/sh -- -c 'uname -r'
```

## Using custom built stage1-kvm images on Semaphore CI

See `examples/semaphore.sh` for an example script which shows the necessary
steps to use a custom stage1-kvm image and serves as a starting point.

### Configuration

Go to `Project Settings` -> `Build Settings` -> `+ Add New Command Line"` and
add `./semaphore.sh` to run the tests. Depending on your project / requirements,
additional settings might be necessary (e.g. install dependencies before).

Go to `Project Settings` -> `Platform Settings` and make sure a platform
with Docker support is selected (at the time of writing this is
`Ubuntu 14.04 LTS v1701 (with Docker support)`).

### Example

For a real world example, see [semaphore.sh from weaveworks/tcptracer-bpf](https://github.com/weaveworks/tcptracer-bpf/blob/master/semaphore.sh).

## FAQ

### Warning: unable to translate guest address

```
...
  Warning: unable to translate guest address 0x410000007c58 to host
  Warning: unable to translate guest address 0x410000007c58 to host

  # KVM session ended normally.
```

This output is coming from LKVM and can be ignored.
