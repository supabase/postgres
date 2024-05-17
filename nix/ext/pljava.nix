{ stdenv, lib, fetchFromGitHub, openssl, openjdk, maven, postgresql, libkrb5, makeWrapper, gcc, pkg-config }:

maven.buildMavenPackage rec {
  pname = "pljava";

  version = "1.6.7";  # Update with the actual version

  src = fetchFromGitHub {
    owner = "tada";
    repo = "pljava";
    rev = "V1_6_7";  # Update with the actual version
    sha256 = "sha256-M17adSLsw47KZ2BoUwxyWkXKRD8TcexDAy61Yfw4fNU=";  # You need to calculate this
    
  };

  mvnParameters = "clean install -Dmaven.test.skip -DskipTests -Dmaven.javadoc.skip=true";  # Update with actual build parameters
  mvnHash = "sha256-lcxRduh/nKcPL6YQIVTsNH0L4ga0LgJpQKgX5IPkRzs=";
  
  nativeBuildInputs = [ makeWrapper maven openjdk postgresql openssl postgresql gcc libkrb5 pkg-config ];
  buildInputs = [ stdenv.cc.cc.lib];
  buildPhase = ''
    export PATH=$(lib.makeBinPath [ postgresql ]):$PATH

  '';
  buildOffline = true;

  # Installing
  installPhase = ''
    set -x


    ls -la pljava-packaging/target
    ls -la .m2/org/postgresql/pljava-packaging/1.6.7
    mkdir -p $out
    cp -r *   $out
    ls -la $out
    java -jar $out/pljava-packaging/target/pljava-pg15.jar
    #makeWrapper $out/bin/java $out/bin/pljava
    set +x
  '';

  # # Post-installation steps
  # postInstall = ''
  #   makeWrapper $out/bin/java $out/bin/pljava
  # '';

  meta = with lib; {
    description = "PL/Java extension for PostgreSQL";
    homepage = https://github.com/tada/pljava;
    license = licenses.bsd3;
    maintainers = [ maintainers.samrose ];  # Update with actual maintainer info
  };
}
