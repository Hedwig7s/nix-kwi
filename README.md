# nix-kwi

Nix flake for [Kwi](https://invent.kde.org/utilities/kwi), the KDE terminal
emulator built on Ghostty's `libghostty-vt`.

Kwi has no tagged release, so this flake builds upstream `master`. A scheduled
workflow refreshes the pin after the build passes.

## Build

Requires Nix with flakes enabled on `x86_64-linux`.

```sh
nix build github:Hedwig7s/nix-kwi
```

The build produces `result/bin/kwi`. Run it from a graphical KDE or Qt session.

## Use as a flake input

```nix
{
  inputs.kwi.url = "github:Hedwig7s/nix-kwi";
}
```

Take the package:

```nix
inputs.kwi.packages.${system}.default
```

Or use the overlay, which adds `pkgs.kwi` and `pkgs.libghostty-vt`:

```nix
nixpkgs.overlays = [ inputs.kwi.overlays.default ];
```

## libghostty-vt

`libghostty-vt` is released separately from the Ghostty app and has its own
version numbers. nixpkgs lags behind, so the flake builds the exact release
that Kwi pins in its own Flatpak manifest. Bumping `kwi-src` therefore also
follows upstream's library bumps, and the same manifest supplies the Zig
version the build needs.

## Update manually

```sh
nix flake update kwi-src
nix build
```

## License

Kwi is licensed under `GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL`.
See the [upstream project](https://invent.kde.org/utilities/kwi) for details.
