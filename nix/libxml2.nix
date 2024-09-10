{ stdenv
, lib
, fetchurl
, pkg-config
, autoreconfHook
, libintl
, python3
, gettext
, ncurses
, findXMLCatalogs
, libiconv
, pythonSupport ? enableShared &&
    (stdenv.hostPlatform == stdenv.buildPlatform || stdenv.hostPlatform.isCygwin || stdenv.hostPlatform.isLinux || stdenv.hostPlatform.isWasi)
, icuSupport ? false
, icu
, enableShared ? !stdenv.hostPlatform.isMinGW && !stdenv.hostPlatform.isStatic
, enableStatic ? !enableShared
, gnome
, testers
, enableHttp ? false
, python ? null  # Add this line to accept 'python' as an argument
}:

let
  # If 'python' is provided, use it; otherwise use 'python3'
  pythonEnv = python3;
in

stdenv.mkDerivation (finalAttrs: {
  pname = "libxml2";
  version = "2.13.3";

  outputs = [ "bin" "dev" "out" "devdoc" ]
    ++ lib.optional pythonSupport "py"
    ++ lib.optional (enableStatic && enableShared) "static";
  outputMan = "bin";

  src = fetchurl {
    url = "mirror://gnome/sources/libxml2/${lib.versions.majorMinor finalAttrs.version}/libxml2-${finalAttrs.version}.tar.xz";
    hash = "sha256-CAXXwYDPCcqtcWZsekWKdPBBVhpTKQJFTaUEfYOUgTg=";
  };

  strictDeps = true;

  nativeBuildInputs = [
    pkg-config
    autoreconfHook
  ];

  buildInputs = lib.optionals pythonSupport [
    pythonEnv
    ncurses
  ];

  propagatedBuildInputs = [
    findXMLCatalogs
  ] ++ lib.optionals stdenv.isDarwin [
    libiconv
  ] ++ lib.optionals icuSupport [
    icu
  ];

  configureFlags = [
    "--exec-prefix=${placeholder "dev"}"
    (lib.enableFeature enableStatic "static")
    (lib.enableFeature enableShared "shared")
    (lib.withFeature icuSupport "icu")
    (lib.withFeature pythonSupport "python")
    (lib.optionalString pythonSupport "PYTHON=${pythonEnv.pythonOnBuildForHost.interpreter}")
  ] ++ lib.optional enableHttp "--with-http";

  installFlags = lib.optionals pythonSupport [
    "pythondir=\"${placeholder "py"}/${pythonEnv.sitePackages}\""
    "pyexecdir=\"${placeholder "py"}/${pythonEnv.sitePackages}\""
  ];

  enableParallelBuilding = true;

  doCheck =
    (stdenv.hostPlatform == stdenv.buildPlatform) &&
    stdenv.hostPlatform.libc != "musl";
  preCheck = lib.optional stdenv.isDarwin ''
    export DYLD_LIBRARY_PATH="$PWD/.libs:$DYLD_LIBRARY_PATH"
  '';

  preConfigure = lib.optionalString (lib.versionAtLeast stdenv.hostPlatform.darwinMinVersion "11") ''
    MACOSX_DEPLOYMENT_TARGET=10.16
  '';

  preInstall = lib.optionalString pythonSupport ''
    substituteInPlace python/libxml2mod.la --replace-fail "$dev/${pythonEnv.sitePackages}" "$py/${pythonEnv.sitePackages}"
  '';

  postFixup = ''
    moveToOutput bin/xml2-config "$dev"
    moveToOutput lib/xml2Conf.sh "$dev"
  '' + lib.optionalString (enableStatic && enableShared) ''
    moveToOutput lib/libxml2.a "$static"
  '';

  passthru = {
    inherit pythonSupport;

    updateScript = gnome.updateScript {
      packageName = "libxml2";
      versionPolicy = "none";
    };
    tests = {
      pkg-config = testers.hasPkgConfigModules {
        package = finalAttrs.finalPackage;
      };
    };
  };

  meta = with lib; {
    homepage = "https://gitlab.gnome.org/GNOME/libxml2";
    description = "XML parsing library for C";
    license = licenses.mit;
    platforms = platforms.all;
    maintainers = with maintainers; [ jtojnar ];
    pkgConfigModules = [ "libxml-2.0" ];
  };
})