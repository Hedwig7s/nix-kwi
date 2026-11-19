{
  description = "Nix flake for Kwi, the KDE terminal emulator built on libghostty-vt";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Kwi has no tagged release yet, so follow upstream master. The GitHub
  # Actions workflow updates this non-flake source pin on its daily schedule.
  inputs.kwi-src = {
    url = "git+https://invent.kde.org/utilities/kwi.git";
    flake = false;
  };

  outputs = { self, nixpkgs, kwi-src }:
    let
      systems = [ "x86_64-linux" ];
      version =
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile "${kwi-src}/CMakeLists.txt");
          line = nixpkgs.lib.findFirst (l: nixpkgs.lib.hasPrefix "project(kwi VERSION " l) "" lines;
          match = builtins.match "project\\(kwi VERSION ([^ )]+).*" line;
        in
        if match == null then "0-unstable" else "${builtins.head match}-unstable";

      binaryRelease = builtins.fromJSON (builtins.readFile ./binary-release.json);

      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      };

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (pkgsFor system));

      libghosttyVt = pkgs: pkgs.callPackage ./libghostty-vt.nix {
        inherit pkgs;
        kwiSrc = kwi-src;
      };

      makeKwiBinary = pkgs:
        if binaryRelease.formatVersion != 2
          || binaryRelease.tag == null
          || binaryRelease.sha256 == null
          || binaryRelease.kwiStorePath == null
          || binaryRelease.libghosttyStorePath == null then
          throw "kwi-bin is not published yet. Wait for the GitHub Actions release workflow to publish binary-release.json."
        else
          let
            archiveUrl = "https://github.com/Hedwig7s/nix-kwi/releases/download/${binaryRelease.tag}/${binaryRelease.archiveName}";
            archive = pkgs.fetchurl {
              url = archiveUrl;
              hash = binaryRelease.sha256;
            };
            runtimeDependencies = import ./runtime-dependencies.nix {
              inherit (pkgs) kdePackages qt6;
            };
          in
          pkgs.stdenvNoCC.mkDerivation {
            pname = "kwi-bin";
            inherit (binaryRelease) version;
            src = archive;

            nativeBuildInputs = [ pkgs.gnutar pkgs.gzip pkgs.patchelf pkgs.python3 ];
            buildInputs = runtimeDependencies;
            # Preserve the same KDE/Qt runtime closure as the source package.
            propagatedBuildInputs = runtimeDependencies;

            dontUnpack = true;
            dontBuild = true;

            installPhase = ''
              runHook preInstall
              stage="$TMPDIR/kwi-release"
              mkdir -p "$stage" "$out/opt/kwi" \
                "$out/opt/kwi-runtime/libghostty-vt" "$out/bin"
              tar -xzf "$src" --strip-components=1 -C "$stage"
              test -x "$stage/app/bin/kwi"
              test -d "$stage/runtime/libghostty-vt/lib"
              cp -a "$stage/app/." "$out/opt/kwi/"
              cp -a "$stage/runtime/libghostty-vt/." \
                "$out/opt/kwi-runtime/libghostty-vt/"

              # cp -a preserves read-only Nix-store modes. Make the copied
              # trees writable so patchelf and text relocation can edit them.
              # chmod -R does not follow symlinks, which may still point at the
              # original build store paths until patch-runtime.py rewrites them.
              chmod -R u+w "$out/opt/kwi" "$out/opt/kwi-runtime/libghostty-vt"

              ${pkgs.python3}/bin/python3 ${./patch-runtime.py} \
                "$out/opt/kwi" \
                "$out/opt/kwi-runtime/libghostty-vt" \
                ${nixpkgs.lib.escapeShellArg binaryRelease.kwiStorePath} \
                ${nixpkgs.lib.escapeShellArg binaryRelease.libghosttyStorePath}

              # Expose the usual Nix package entry point while keeping the
              # bundled application and extra shared library in separate trees.
              ln -s ../opt/kwi/bin/kwi "$out/bin/kwi"
              runHook postInstall
            '';

            doInstallCheck = true;
            installCheckPhase = ''
              test -x "$out/opt/kwi/bin/kwi"
              test -L "$out/bin/kwi"
              test -x "$out/bin/kwi"
              find "$out/opt/kwi-runtime/libghostty-vt/lib" -maxdepth 1 \
                \( -type f -o -type l \) -name 'libghostty-vt.so*' -print -quit | grep -q .
            '';

            meta = {
              description = "Prebuilt Kwi terminal emulator from a GitHub Release tarball";
              homepage = "https://invent.kde.org/utilities/kwi";
              license = with pkgs.lib.licenses; [ gpl2Only gpl3Only ];
              mainProgram = "kwi";
              platforms = [ "x86_64-linux" ];
            };
          };
    in
    {
      kwiVersion = version;
      overlays.default = final: prev: {
        libghostty-vt = libghosttyVt prev;
        kwi = final.callPackage ./package.nix {
          inherit version;
          src = kwi-src;
        };
        kwi-bin = makeKwiBinary final;
      };

      packages = forAllSystems (pkgs: {
        default = pkgs.kwi;
        kwi = pkgs.kwi;
        kwi-source = pkgs.kwi;
        kwi-bin = pkgs.kwi-bin;
        libghostty-vt = pkgs.libghostty-vt;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          inputsFrom = [ pkgs.kwi ];
        };
      });
    };
}
