# Releases

`minfwm` releases are tagged using standard versioning in the format `v<MAJOR>.<MINOR>` (for example, `v1.1`, `v1.2`, `v2.0`).

---

## Installing & Updating

### Homebrew (Recommended)

To install or upgrade to the latest stable release:

```sh
brew update
brew upgrade snusxd/minfwm/minfwm
```

After updating, restart the background service:

```sh
minfwm restart
```

### Pre-built Binaries

Standalone archive packages (`minfwm-macos.tar.gz` and `SHA256SUMS`) are published with every tagged release on the [GitHub Releases page](https://github.com/snusxd/minfwm/releases).

---

## Checking Your Version

You can verify the currently installed version via the CLI:

```sh
minfwm version
```

For development builds compiled from source, display the short Git commit hash with:

```sh
minfwm version --dev
```
