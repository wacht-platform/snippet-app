# Linux Desktop Build & Verification

This document records the Linux desktop build configuration, system dependencies, packaging, and runtime verification for the Snippet client app.

## Prerequisites

On Debian/Ubuntu-based systems, install the Flutter Linux desktop toolchain and library dependencies:

```bash
sudo apt update && sudo apt install -y \
  cmake \
  ninja-build \
  pkg-config \
  libgtk-3-dev \
  libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev \
  libegl1 \
  libgl1-mesa-dri
```

### Dependency Notes
- **GTK3 (`libgtk-3-dev`)**: Required by the Flutter Linux desktop GTK runner.
- **GStreamer (`libgstreamer1.0-dev`, `libgstreamer-plugins-base1.0-dev`)**: Required by `audioplayers_linux` for playback.
- **EGL / Mesa (`libegl1`, `libgl1-mesa-dri`)**: Required at runtime by the Flutter engine for OpenGL/EGL surface rendering.

## Building the Linux Release Bundle

1. Fetch dependencies:
   ```bash
   flutter pub get
   ```

2. Compile the native Linux release application:
   ```bash
   flutter build linux --release
   ```

The compiled relocatable bundle is output to:
`build/linux/x64/release/bundle/`

Contents:
- `snippet`: Main executable (dynamic link to GTK3 and Flutter engine with `$ORIGIN/lib` RUNPATH)
- `data/`: Flutter assets and ICU data (`icudtl.dat`, fonts, asset catalog)
- `lib/`: Shared libraries (`libflutter_linux_gtk.so`, `libapp.so`, and compiled plugin shared objects)

## Verification Receipt

- **Build Target**: Linux x86_64 Release Bundle
- **Verified Environment**: Instabox microVM (`technoxi-ise-demo`) running Debian trixie on XFCE desktop (`DISPLAY=:1`, 1280x800 resolution)
- **Shared Library Resolution**: `ldd build/linux/x64/release/bundle/snippet` confirmed all core and plugin dynamic libraries resolved with 0 missing symbols.
- **Runtime Execution**: Successfully launched on `DISPLAY=:1` under XFCE with hardware/Mesa software rasterisation, verified window creation (`0x01e00003 "snippet"`), clean log output without errors or segmentation faults.
- **Daemon Connectivity**: Verified connection to a local `snippet serve` daemon instance (`127.0.0.1:8787`).

## Packaging Universal Release Archive

To package a standalone, relocatable distribution archive for Linux x64:

1. Stage bundle and launcher files:
   - Compiled Flutter release bundle (`build/linux/x64/release/bundle/*`)
   - Shell launcher wrapper (`snippet.sh`) with dynamic `LD_LIBRARY_PATH="${DIR}/lib:${LD_LIBRARY_PATH:-}"`
   - Freedesktop application entry (`snippet.desktop`)
   - High-resolution app icon (`snippet.png`)

2. Create tarball:
   ```bash
   mkdir -p dist
   tar -czf dist/snippet-linux-x64.tar.gz -C build/dist_staging snippet-linux-x64
   sha256sum dist/snippet-linux-x64.tar.gz > dist/snippet-linux-x64.tar.gz.sha256
   ```

3. Standalone Verification:
   The archive was transferred to an isolated directory on Instabox VM `technoxi-ise-demo` (`/data/workspace/test-dist/`), extracted, and executed via `./snippet.sh` on `DISPLAY=:1`. The GUI launched with complete library resolution and zero runtime errors.
