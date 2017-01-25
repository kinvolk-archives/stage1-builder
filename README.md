# stage1-builder

Experimental build script for custom rkt stage1-kvm images.

## Usage

```
./builder
```

The only supported kernel right now is 4.9.z (the latest stable at the
time of writing) and picked by default.

A successful build produces a `stage1-kvm-linux-4.9.4.aci` file to be
used as rkt stage1 with `--stage1-path=...`.
