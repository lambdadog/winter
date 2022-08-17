{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  packages = with pkgs; [
    pkg-config

    wayland wayland-protocols wayland-scanner.dev
    wlroots libxkbcommon pixman

    guile_3_0
  ];
}
