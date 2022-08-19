{ pkgs ? import <nixpkgs> {} }:

let
  debug-guile = pkgs.enableDebugging (pkgs.guile_3_0.overrideAttrs (old: {
    dontStrip = true;
  }));
in pkgs.mkShell {
  packages = with pkgs; [
    pkg-config

    wayland wayland-protocols wayland-scanner.dev
    wlroots libxkbcommon pixman

    debug-guile
  ];
}
