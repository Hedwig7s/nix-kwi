# nix-kwi

Nix flake for [Kwi](https://invent.kde.org/utilities/kwi), the KDE terminal
emulator built on Ghostty's `libghostty-vt`.

Kwi has no tagged upstream release, so this flake follows upstream `master`.
GitHub Actions builds the application, signs its complete Nix runtime closure,
and publishes that cache in **one tarball asset** on a GitHub Release.

There are two intentionally different package outputs:

- `kwi` / `kwi-source`: builds Kwi from source on the machine performing the
  build.
- `kwi-bin`: uses the prebuilt Kwi store path and runtime closure from the
  GitHub Release. It does not depend on or invoke the source Kwi derivation.
  Only a tiny symlink wrapper is built locally.

## Install the prebuilt binary

```sh
nix --accept-flake-config profile install github:Hedwig7s/nix-kwi#kwi-bin
```

The GitHub Release has one asset:

```text
nix-kwi-binary-cache.tar.gz
```

It contains a standard Nix binary-cache directory:

```text
nix-cache-info
<store-hash>.narinfo
nar/<nar-file>
```

The flake declares that archive as a locked, non-flake tarball input named `kwi-cache-archive`. Nix's
normal flake fetcher downloads and extracts it into the store before evaluating
the package. The resulting store directory is used as a local `file://` binary
substituter. `flake.lock` pins the extracted contents by NAR hash, and each
NAR is also covered by the generated binary-cache signing key. There is no
`fetchClosure` or `fetchTarball` builtin call during restricted flake
evaluation, and no per-NAR GitHub Release asset list.

The `kwi-bin` output refers to the exact prebuilt Kwi store path using
`builtins.appendContext`. Nix retrieves that path and its full closure from
the extracted local cache. The local derivation creates only a symlink; it
does not compile Kwi, Qt, Zig, or `libghostty-vt`.

### Consuming Kwi from another flake (for example NixOS dotfiles)

Nix does not apply an input flake's `nixConfig` to the root flake. Add the
current cache directory and public key from this repository's
`binary-cache.json` to the **root** flake's `nixConfig` (or to the host's
`/etc/nix/nix.conf`):

```nix
nixConfig = {
  extra-substituters = [ "file://<absolute-cacheStorePath>" ];
  extra-trusted-public-keys = [ "<publicKey>" ];
};
```

For `/etc/nix/nix.conf`, use whitespace-separated values:

```ini
extra-substituters = file://<absolute-cacheStorePath>
extra-trusted-public-keys = <publicKey>
```

`cacheStorePath` is the extracted tarball input's store path recorded in
`binary-cache.json`. Because the tarball is a locked transitive flake input,
Nix downloads and extracts it as part of resolving the Kwi input. The file
substituter path must be configured in the root flake or host Nix settings so
the current Nix invocation can use it. `nix.settings` in a NixOS module updates
the daemon configuration for subsequent invocations; it does not retroactively
change the current `nh` evaluation.

The signing key is regenerated for each published release. When updating the
Kwi flake input, also update the root flake's cache path and public key from the
new `binary-cache.json`.

The workflow removes legacy `binary-cache` input declarations and stale lock
entries before any update. The archive input is named `kwi-cache-archive` and
always uses an explicit `tarball+https://...` URL. Do not use registry-style
references for the archive: Nix would interpret them as indirect flake aliases
and fail when the alias is absent.

## Build from source instead

The source derivation remains available as `kwi` (also named `kwi-source`):

```sh
nix build .#kwi --print-build-logs
```

The default package is still the source derivation:

```sh
nix build .#
```

The source package is not redirected through the GitHub Release cache. Nix
uses its normal configured substituters for ordinary dependencies and builds
Kwi itself from the pinned upstream source when no substitute exists.

## Use as a flake input

```nix
{
  inputs.kwi.url = "github:Hedwig7s/nix-kwi";
}
```

Use the prebuilt output:

```nix
inputs.kwi.packages.${system}.kwi-bin
```

Or select the source derivation explicitly:

```nix
inputs.kwi.packages.${system}.kwi-source
```

Remember to configure the extracted cache directory and public signing key in
the root flake's `nixConfig` or in `/etc/nix/nix.conf` when consuming Kwi as an
input. The current values are recorded in `binary-cache.json`.

## GitHub Actions and releases

`.github/workflows/update.yml` runs daily, on pushes to `main`, and on manual
dispatch. It first removes legacy registry-style `binary-cache` references, normalizes the
`kwi-cache-archive` input, and locks the explicit GitHub tarball URL when a
release exists. Scheduled/manual
runs then refresh the `kwi-src` lock-file pin. The workflow then:

1. Builds Kwi from source on GitHub Actions.
2. Signs the complete runtime closure, including `libghostty-vt`.
3. Creates a standard Nix binary-cache directory with `.narinfo` files and
   `nar/` contents.
4. Tars that directory into `nix-kwi-binary-cache.tar.gz` and uploads only
   that single asset to a GitHub Release.
5. Adds the tarball as a locked non-flake `kwi-cache-archive` input, records its extracted
   store path and the public signing key in `binary-cache.json`, and configures
   the literal `nixConfig` substituter for this flake when used as the root.
6. Builds `.#kwi-bin` to verify that the cache substitutes the prebuilt Kwi
   closure without compiling it.

The private signing key is generated on the Actions runner and is never
committed or uploaded. Only public cache files and the public verification key
are published.

## libghostty-vt

`libghostty-vt` is released separately from the Ghostty app and has its own
version numbers. nixpkgs lags behind, so the flake builds the exact release
that Kwi pins in its own Flatpak manifest. Bumping `kwi-src` therefore also
follows upstream's library bumps, and the same manifest supplies the Zig
version the build needs.

## Update manually

```sh
nix flake update kwi-src
nix build .#kwi-source --print-build-logs
```

The GitHub Actions workflow publishes releases automatically when run on the
repository's `main` branch.

## License

Kwi is licensed under `GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL`.
See the [upstream project](https://invent.kde.org/utilities/kwi) for details.
