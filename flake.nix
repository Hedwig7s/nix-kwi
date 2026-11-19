{
  description = "Nix flake for Kwi, the KDE terminal emulator built on libghostty-vt";

  # These settings are filled in by the release workflow. Keep nixConfig as a
  # literal attribute set: the flake evaluator inspects it before outputs.
  # BEGIN GENERATED BINARY CACHE CONFIG
  nixConfig = {
    extra-substituters = [ ];
    extra-trusted-public-keys = [ ];
  };
  # END GENERATED BINARY CACHE CONFIG

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Kwi has no tagged release yet, so the flake builds upstream master.
  # .github/workflows/update.yml bumps this pin every day.
  inputs.kwi-src = {
    url = "git+https://invent.kde.org/utilities/kwi.git";
    flake = false;
  };

  # This non-flake input is a tar.gz of the standard Nix binary-cache layout.
  # The workflow writes an explicit tarball+https URL under the distinct input
  # name kwi-cache-archive. Legacy binary-cache registry aliases are removed.
  # BEGIN GENERATED BINARY CACHE INPUT
  inputs.kwi-cache-archive = {
    url = "path:./no-cache";
    flake = false;
  };
  # END GENERATED BINARY CACHE INPUT

  outputs =
    {
      self,
      nixpkgs,
      kwi-src,
      kwi-cache-archive,
    }:
    let
      systems = [ "x86_64-linux" ];

      kwiSrc = kwi-src;

      # Metadata is committed after the release archive has been published.
      # The non-flake input above is fetched and unpacked by Nix's flake
      # fetcher; cacheStorePath records its exact extracted store path.
      binaryCache = builtins.fromJSON (builtins.readFile ./binary-cache.json);
      # The input is always declared (Nix would otherwise invent an indirect
      # flake:kwi-cache-archive input). Until a release exists it points at the
      # empty ./no-cache placeholder, so key off the metadata instead of null.
      hasCache = binaryCache.tag != null;
      binaryCachePath = if hasCache then builtins.toString kwi-cache-archive else null;

      # appendContext marks Kwi's exact prebuilt store path as a required path
      # dependency. The extracted cache input supplies its NAR and every
      # transitive runtime reference. kwi-bin never falls back to source build.
      kwiBinaryStorePath =
        if !hasCache || binaryCache.publicKey == null || binaryCache.storePath == null || binaryCache.archiveHash == null || binaryCache.cacheStorePath == null then
          throw "kwi-bin is unavailable: no complete GitHub Release binary cache is locked in this flake. Run the 'Build and publish Kwi GitHub Release' workflow and update flake.lock."
        else if binaryCachePath != binaryCache.cacheStorePath then
          throw "kwi-bin binary cache input does not match binary-cache.json; run 'nix flake lock' to refresh the extracted cache input."
        else if !(builtins ? appendContext) then
          throw "kwi-bin requires Nix with builtins.appendContext support."
        else
          builtins.appendContext binaryCache.storePath {
            "${binaryCache.storePath}" = {
              path = true;
            };
          };

      # Kwi tracks libghostty-vt independently of the Ghostty app, and nixpkgs
      # lags behind both. Build the library release that Kwi pins in its
      # Flatpak manifest instead of reusing nixpkgs' snapshot.
      libghosttyVt = pkgs: pkgs.callPackage ./libghostty-vt.nix { inherit kwiSrc pkgs; };

      # Kwi has no release tags yet, so read the CMake project version and mark
      # the build as unstable.
      version =
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile "${kwi-src}/CMakeLists.txt");
          line = nixpkgs.lib.findFirst (l: nixpkgs.lib.hasPrefix "project(kwi VERSION " l) "" lines;
        in
        if line == "" then
          "0-unstable"
        else
          let
            words = builtins.filter (w: w != "") (
              nixpkgs.lib.splitString " " (nixpkgs.lib.removePrefix "project(kwi VERSION " line)
            );
          in
          "${nixpkgs.lib.head words}-unstable";

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (pkgsFor system));
    in
    {
      kwiVersion = version;
      inherit binaryCachePath;

      overlays.default =
        final: prev:
        let
          libghostty-vt = libghosttyVt prev;
          kwi = final.callPackage ./package.nix {
            inherit version;
            src = kwi-src;
          };
          kwi-bin =
            if !hasCache then
              throw "kwi-bin is unavailable: no binary cache tarball input is locked."
            else
              final.runCommand "kwi-bin-prebuilt" {
                # Keep the extracted tarball input alive and available as the
                # local binary-cache substituter while Nix realizes Kwi's path.
                cacheDir = kwi-cache-archive;
                meta = {
                  description = "Prebuilt Kwi terminal fetched from the GitHub Release binary cache tarball";
                  homepage = "https://invent.kde.org/utilities/kwi";
                  license = with final.lib.licenses; [ gpl2Only gpl3Only ];
                  mainProgram = "kwi";
                  platforms = final.lib.platforms.linux;
                };
              } ''
                # This output is only a symlink to the already-fetched Kwi store
                # path. No CMake, Qt, Zig, or application compilation happens here.
                test -f "$cacheDir/nix-cache-info"
                ln -s ${kwiBinaryStorePath} "$out"
              '';
        in
        {
          inherit libghostty-vt kwi kwi-bin;
        };

      packages = forAllSystems (pkgs: {
        default = pkgs.kwi;
        kwi = pkgs.kwi;
        kwi-source = pkgs.kwi;
        kwi-bin = pkgs.kwi-bin;
        inherit (pkgs) libghostty-vt;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          inputsFrom = [ pkgs.kwi ];
        };
      });
    };
}
