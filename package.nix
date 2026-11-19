{
  lib,
  stdenv,
  cmake,
  ninja,
  pkg-config,
  gettext,
  kdePackages,
  qt6,
  libghostty-vt,
  src,
  version ? "0-unstable",
}:

stdenv.mkDerivation {
  pname = "kwi";
  inherit src version;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    gettext
    kdePackages.extra-cmake-modules
    qt6.qttools
    kdePackages.wrapQtAppsHook
  ];

  buildInputs = (import ./runtime-dependencies.nix { inherit kdePackages qt6; }) ++ [
    libghostty-vt
  ];

  cmakeFlags = [
    "-DBUILD_TESTING=OFF"
    # The KPart is only useful when another QWidget app hosts it. Keep it on by
    # default so Dolphin, Kate and Yakuake can use Kwi as their terminal.
    "-DBUILD_KPART=ON"
  ];

  meta = {
    description = "Modern and fast terminal for KDE Plasma and other desktops";
    homepage = "https://invent.kde.org/utilities/kwi";
    license = with lib.licenses; [
      gpl2Only
      gpl3Only
    ];
    mainProgram = "kwi";
    platforms = lib.platforms.linux;
  };
}
