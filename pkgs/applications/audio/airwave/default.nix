{ stdenv, multiStdenv, cmake, fetchFromGitHub, file, libX11, makeWrapper
, qt5, fetchurl, unzip, wine
}:

let

  version = "1.3.3";

  airwave-src = fetchFromGitHub {
    owner = "phantom-code";
    repo = "airwave";
    rev = version;
    sha256 = "1ban59skw422mak3cp57lj27hgq5d3a4f6y79ysjnamf8rpz9x4s";
  };

  vst-sdk = stdenv.mkDerivation rec {
    name = "vstsdk366_27_06_2016_build_61";
    nativeBuildInputs = [ unzip ];
    src = fetchurl {
      url = "https://www.steinberg.net/sdk_downloads/${name}.zip";
      sha256 = "05gsr13bpi2hhp34rvhllsvmn44rqvmjdpg9fsgfzgylfkz0kiki";
    };
    installPhase = "cp -r . $out";
    meta.license = stdenv.lib.licenses.unfree;
  };

  wine-wow64 = wine.override {
    wineRelease = "stable";
    wineBuild = "wineWow";
  };

  wine-xembed = wine-wow64.overrideDerivation (oldAttrs: {
    patchFlags = [ "-p2" ];
    patches = [ "${airwave-src}/fix-xembed-wine-windows.patch" ];
  });

in

multiStdenv.mkDerivation {
  name = "airwave-${version}";

  src = airwave-src;

  nativeBuildInputs = [ cmake makeWrapper qt5.wrapQtAppsHook ];

  buildInputs = [ file libX11 qt5.qtbase wine-xembed ];

  postPatch = ''
    # Binaries not used directly should land in libexec/.
    substituteInPlace src/common/storage.cpp --replace '"/bin"' '"/libexec"'

    # For airwave-host-32.exe.so, point wineg++ to 32-bit versions of
    # these libraries, as $NIX_LDFLAGS contains only 64-bit ones.
    substituteInPlace src/host/CMakeLists.txt --replace '-m32' \
      '-m32 -L${wine-xembed}/lib -L${wine-xembed}/lib/wine -L${multiStdenv.cc.libc.out}/lib/32'
  '';

  # libstdc++.so link gets lost in 64-bit executables during
  # shrinking.
  dontPatchELF = true;

  # Cf. https://github.com/phantom-code/airwave/issues/57
  hardeningDisable = [ "format" ];

  cmakeFlags = [ "-DVSTSDK_PATH=${vst-sdk}" ];

  postInstall = ''
    mv $out/bin $out/libexec
    mkdir $out/bin
    mv $out/libexec/airwave-manager $out/bin
    wrapProgram $out/libexec/airwave-host-32.exe --set WINELOADER ${wine-xembed}/bin/wine
    wrapProgram $out/libexec/airwave-host-64.exe --set WINELOADER ${wine-xembed}/bin/wine64
  '';

  meta = with stdenv.lib; {
    description = "WINE-based VST bridge for Linux VST hosts";
    longDescription = ''
      Airwave is a wine based VST bridge, that allows for the use of
      Windows 32- and 64-bit VST 2.4 audio plugins with Linux VST
      hosts. Due to the use of shared memory, only one extra copying
      is made for each data transfer. Airwave also uses the XEMBED
      protocol to correctly embed the plugin editor into the host
      window.
    '';
    homepage = https://github.com/phantom-code/airwave;
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    maintainers = with maintainers; [ michalrus ];
    hydraPlatforms = [];
  };
}
