final: prev: {
  # override the version of gdal used with postgis with the small version.
  # significantly reduces overall closure size
  gdal = prev.gdalMinimal.override {
    /* other features can be enabled, reference:
        https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/libraries/gdal/default.nix
        */

    # useHDF = true;
    # useArrow = true;
    # useLibHEIF = true;
    # ...
  };
}
