# nix-kwi

Nix flake for [Kwi](https://invent.kde.org/utilities/kwi), the KDE terminal
emulator built on Ghostty's `libghostty-vt`.

Kwi has no tagged upstream release, so this flake follows upstream `master`.
GitHub Actions builds the application and publishes one conventional Linux
binary archive per upstream build.

## Install the prebuilt application

```sh
nix profile install github:Hedwig7s/nix-kwi#kwi-bin
```

The GitHub Release contains one ordinary gzip-compressed tar archive:

```text
kwi-x86_64-linux.tar.gz
```

It contains an installed application tree, not a Nix binary cache:

```text
kwi-release/
├── app/                   # installed Kwi application tree
├── runtime/
│   └── libghostty-vt/     # matching shared-library output
└── README.txt
```

The flake downloads that archive with `fetchurl`, verifies its SHA-256 hash,
extracts the application and bundled runtime into separate directories, then
relocates both trees' Nix store references. The Nix output exposes
`$out/bin/kwi` as a symlink to the relocated executable under `$out/opt/kwi`,
with the extra library under `$out/opt/kwi-runtime/libghostty-vt`.
The Qt/KDE runtime libraries are ordinary dependencies from the flake's locked
nixpkgs revision and use the normal Nix binary cache. Kwi and libghostty-vt are
not compiled on the installing host.

There is no custom substituter, signing key, generated `nixConfig`, binary
cache input, tarball flake input, registry alias, `fetchClosure`, or
`appendContext` requirement.

## Build from source instead

The source derivation remains available as `kwi` and `kwi-source`:

```sh
nix build .#kwi --print-build-logs
```

The default package is also the source derivation:

```sh
nix build .#
```

## Use as a flake input

```nix
{
  inputs.kwi.url = "github:Hedwig7s/nix-kwi";
}
```

Install the prebuilt package in NixOS:

```nix
{ inputs, pkgs, ... }:
{
  environment.systemPackages = [
    inputs.kwi.packages.${pkgs.system}.kwi-bin
  ];
}
```

Or select the source package explicitly:

```nix
inputs.kwi.packages.${pkgs.system}.kwi-source
```

No additional cache configuration is needed when using the flake as an input.

## GitHub Actions and releases

`.github/workflows/update.yml` runs daily, on pushes to `main`, and on manual
dispatch. Scheduled/manual runs update the pinned upstream Kwi source. The
workflow then:

1. Builds `.#kwi` and `.#libghostty-vt` on GitHub Actions.
2. Copies the installed Kwi application tree and libghostty-vt output into
   separate `app/` and `runtime/` directories in a fresh temporary workspace.
   This avoids following any `libghostty-vt` symlink that Kwi may have in its
   own install tree and avoids stale temporary-directory ownership.
3. Publishes one `kwi-x86_64-linux.tar.gz` asset on a GitHub Release.
4. Records the release URL, SHA-256 hash, and original store paths in
   `binary-release.json`.
5. Builds `.#kwi-bin` to verify extraction and runtime-path relocation without
   building Kwi or libghostty-vt again.

The binary package uses the same runtime dependency list as the source package.
Qt/KDE libraries are obtained as normal Nix substitutes; the custom
libghostty-vt library itself is included in the release archive.

## License

Kwi is licensed under
`GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL`.
See the [upstream project](https://invent.kde.org/utilities/kwi) for details.
