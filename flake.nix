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
        if binaryRelease.formatVersion != 3
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
          pkgs.stdenv.mkDerivation {
            pname = "kwi-bin";
            inherit (binaryRelease) version;
            src = archive;

            # The source package's bin/kwi is already a Qt wrapper around
            # bin/.kwi-wrapped. Do not wrap that script again: install the raw
            # ELF executable as our public launcher and apply one Qt wrapper
            # with the runtime paths from this derivation.
            nativeBuildInputs = [
              pkgs.gnutar
              pkgs.gzip
              pkgs.patchelf
              pkgs.python3
              pkgs.kdePackages.wrapQtAppsHook
              # Prebuilt ELFs ship with no usable RPATH to Qt/KF6/GL libs.
              # Resolve every NEEDED entry against buildInputs; build fails
              # loudly if any is unsatisfied.
              pkgs.autoPatchelfHook
            ];
            buildInputs = runtimeDependencies ++ [
              pkgs.qt6.qtbase
              pkgs.stdenv.cc.cc.lib # libstdc++
              pkgs.libxkbcommon
              pkgs.libglvnd # libGLX, libOpenGL
              (pkgs.libx11 or pkgs.xorg.libX11)
            ];
            propagatedBuildInputs = runtimeDependencies;
            dontWrapQtApps = true;

            dontUnpack = true;
            dontBuild = true;

            installPhase = ''
              runHook preInstall
              stage="$TMPDIR/kwi-release"
              mkdir -p "$stage" "$out/opt/kwi" \
                "$out/opt/kwi-runtime/libghostty-vt" "$out/bin"
              tar -xzf "$src" --strip-components=1 -C "$stage"
              # The source derivation's public bin/kwi is a Qt shell wrapper;
              # .kwi-wrapped is the actual ELF executable. The final package
              # must wrap the ELF, not wrap the already-wrapped script again.
              test -x "$stage/app/bin/kwi"
              test -x "$stage/app/bin/.kwi-wrapped"
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

              # Install the raw ELF rather than the source output's existing
              # Qt wrapper. wrapQtApp below will add the Qt/KDE environment once.
              install -m755 "$out/opt/kwi/bin/.kwi-wrapped" "$out/bin/kwi"

              # Upstream installs desktop integration below
              # share/{applications,icons}, but the app tree is bundled under
              # /opt/kwi. Promote those files to the standard output locations
              # so NixOS/Plasma can discover the launcher and its icon.
              ${pkgs.python3}/bin/python3 ${./install-desktop.py} \
                "$out/opt/kwi" "$out" "$out/bin/kwi"
              runHook postInstall
            '';

            # Retain the Qt dependency paths collected from buildInputs, but
            # disable the automatic output scan (which would re-wrap nested
            # launchers in /opt/kwi). Add Kwi's own QML and plugin directories,
            # which live below /opt/kwi rather than the output root.
            preFixup = ''
              addAutoPatchelfSearchPath "$out/opt/kwi/lib"
              addAutoPatchelfSearchPath "$out/opt/kwi-runtime/libghostty-vt/lib"
              wrapQtApp "$out/bin/kwi" \
                --prefix QT_PLUGIN_PATH : "$out/opt/kwi/lib/qt-6/plugins" \
                --prefix NIXPKGS_QT6_QML_IMPORT_PATH : "$out/opt/kwi/lib/qt-6/qml" \
                --prefix XDG_DATA_DIRS : "$out/opt/kwi/share"
            '';

            doInstallCheck = true;
            installCheckPhase = ''
              # The public executable is the single Qt wrapper around the raw
              # ELF. The upstream wrapper is retained only as bundle content;
              # it is not on the launch path.
              test -x "$out/bin/kwi"
              # Catch unresolved shared libraries at build time.
              for f in "$out/bin/.kwi-wrapped" "$out"/opt/kwi/lib/*.so*; do
                [ -f "$f" ] || continue
                if ldd "$f" 2>&1 | grep -q 'not found'; then
                  echo "unresolved libs in $f:" >&2
                  ldd "$f" | grep 'not found' >&2
                  exit 1
                fi
              done
              test -x "$out/opt/kwi/bin/kwi"
              test -x "$out/opt/kwi/bin/.kwi-wrapped"
              grep -q 'NIXPKGS_QT6_QML_IMPORT_PATH' "$out/bin/kwi"
              test -d "$out/share/applications"
              desktop_file=$(find "$out/share/applications" -maxdepth 1 \
                -type f -name '*.desktop' -print -quit)
              test -n "$desktop_file"
              desktop_count=0
              for desktop_file in "$out"/share/applications/*.desktop; do
                [ -f "$desktop_file" ] || continue
                desktop_count=$((desktop_count + 1))
                grep -Fq -- "Exec=$out/bin/kwi" "$desktop_file"
                grep -Fq -- "TryExec=$out/bin/kwi" "$desktop_file"
              done
              test "$desktop_count" -gt 0
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
