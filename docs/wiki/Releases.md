# Releases

Releases use `vMAJOR.N`, for example `v1.1` and `v1.2`. `VERSION_MAJOR` stores
the current major number. The release workflow assigns `N` by finding the
largest existing release tag for that major and adding one. It then builds,
runs CTest, packages the binaries, and publishes a GitHub Release with the new
tag and generated notes.

## Publish a release

1. Merge the changes intended for release into `main` and wait for the CI
   workflow to pass.
2. In GitHub, open **Actions → Release → Run workflow**. Select `main` and run
   the workflow. The version number is assigned automatically.
3. Check the new GitHub Release and its `minfwm-macos.tar.gz` and `SHA256SUMS`
   assets.

The release workflow can run only from `main`. It is serialized so two release
runs cannot choose the same next number. It does not publish automatically on
every push; use it when you decide the changes are ready for a release.

## Change the major number

For a major version change, edit `VERSION_MAJOR` to the desired integer, merge
that change to `main`, then run the release workflow. For example, changing it
from `1` to `2` makes the next release `v2.1`. Existing tags for older major
versions remain unchanged.

## Check the version

The release binary reports its release tag with `minfwm version`. Local builds
continue to report their short Git commit hash. `minfwm version --dev` reports
the latest local commit hash.
