# Releases

`minfwm` uses version tags in the format `v<MAJOR>.<N>` (for example, `v1.1`, `v1.2`, `v2.0`).

- The major version number is defined in the `VERSION_MAJOR` file at the root of the repository.
- The minor number `N` is automatically calculated by finding the highest existing tag for that major version and incrementing it by one.

---

## Publishing a Release

Releases are built and published via GitHub Actions:

1. **Merge Changes**: Ensure all changes are merged into `main` and continuous integration passes.
2. **Trigger Release**:
   - Navigate to the **Actions** tab in the GitHub repository.
   - Select the **Release** workflow from the left sidebar.
   - Click **Run workflow**, choose the `main` branch, and click the green button.
3. **Artifacts**:
   - The workflow builds the project, runs tests, packages the release archives (`minfwm-macos.tar.gz` and `SHA256SUMS`), and publishes a new GitHub Release.

---

## Changing the Major Version

To release a new major version:

1. Edit the integer in the `VERSION_MAJOR` file (for example, change `1` to `2`).
2. Commit and merge this change to `main`.
3. The next release workflow run will publish `v2.0`.

---

## Checking Your Version

Check the installed `minfwm` version via the CLI:

```sh
minfwm version
```

For development builds, view the current Git commit hash with:

```sh
minfwm version --dev
```
