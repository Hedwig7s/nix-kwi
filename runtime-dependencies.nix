# Runtime libraries required by Kwi. Keep this list shared between the source
# package and the prebuilt package so their Nixpkgs store paths match.
{ kdePackages, qt6 }:
[
  kdePackages.kirigami
  kdePackages.kirigami-addons
  kdePackages.kirigami-app-components
  kdePackages.qqc2-desktop-style
  kdePackages.kcoreaddons
  kdePackages.kconfig
  kdePackages.kdbusaddons
  kdePackages.kguiaddons
  kdePackages.ki18n
  kdePackages.kio
  kdePackages.kitemmodels
  kdePackages.knotifications
  kdePackages.kparts
  kdePackages.kpty
  kdePackages.kwindowsystem
  kdePackages.kwidgetsaddons
  kdePackages.kxmlgui
  qt6.qtdeclarative
  qt6.qtshadertools
  qt6.qtsvg
]
