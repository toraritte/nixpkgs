{ fetchFromGitHub, fetchpatch, stdenv, lib, pkg-config, autoreconfHook
, ncurses, gnutls, readline
, openssl, perl, sqlite, libjpeg, speex, pcre, libuuid
, ldns, libedit, yasm, which, libsndfile, libtiff

, callPackage

, SystemConfiguration

, modules ? null
, nixosTests
}:

let

availableModules = callPackage ./modules.nix { };

# the default list from v1.8.7, except with applications/mod_signalwire also disabled
defaultModules = mods: with mods; [
  applications.commands
  applications.conference
  applications.db
  applications.dptools
  applications.enum
  applications.esf
  applications.expr
  applications.fifo
  applications.fsv
  applications.hash
  applications.httapi
  applications.sms
  applications.spandsp
  applications.valet_parking
  applications.voicemail

  applications.curl

  codecs.amr
  codecs.b64
  codecs.g723_1
  codecs.g729
  codecs.h26x
  codecs.opus

  databases.mariadb
  databases.pgsql

  dialplans.asterisk
  dialplans.xml

  endpoints.loopback
  endpoints.rtc
  endpoints.skinny
  endpoints.sofia
  endpoints.verto

  event_handlers.cdr_csv
  event_handlers.cdr_sqlite
  event_handlers.event_socket

  formats.local_stream
  formats.native_file
  formats.png
  formats.sndfile
  formats.tone_stream

  languages.lua

  loggers.console
  loggers.logfile
  loggers.syslog

  say.en

  xml_int.cdr
  xml_int.rpc
  xml_int.scgi
] ++ lib.optionals stdenv.isLinux [ endpoints.gsmopen ];

enabledModules = (if modules != null then modules else defaultModules) availableModules;

modulesConf = let
  lst = builtins.map (mod: mod.path) enabledModules;
  str = lib.strings.concatStringsSep "\n" lst;
  in builtins.toFile "modules.conf" str;

in

stdenv.mkDerivation rec {
  pname = "freeswitch";
  version = "0.1";
  src = fetchFromGitHub {
    # owner = "signalwire";
    owner = "rucc";
    repo = pname;
    # rev = "v${version}";
    rev = "3f2f1e6ae65b721101e6720c25cf016a5682a09a";
    sha256 = "0000000000000000000000000000000000000000000000000000";
  };

  # HOW TO GET SHA256 HASH
  # ----------------------
  # $ nix-shell . -A freeswitch
  # [..]
  # wanted: sha256:0000000000000000000000000000000000000000000000000000
  # got:    sha256:0iqy2pblpq4771mfsl06hm78qnsgsf7vasvlzm8m7r06mh3gfc3c

  # QUESTION: Once dropping into `nix-shell`, how do I know what phases to execute by looking at this?
  # QUESTION: When dropping into `nix-shell`, is this Nix expression (i.e., `freeswitch/default.nix`) executed?

  patches = [
    # https://github.com/signalwire/freeswitch/pull/812 fix mod_spandsp, mod_gsmopen build, drop when updating from 1.10.5
    (fetchpatch {
      url = "https://github.com/signalwire/freeswitch/commit/51fba83ed3ed2d9753d8e6b13e13001aca50b493.patch";
      sha256 = "0h2bmifsyyasxjka3pczbmqym1chvz91fmb589njrdbwpkjyvqh3";
    })
  ];
  postPatch = ''
    patchShebangs     libs/libvpx/build/make/rtcd.pl
    substituteInPlace libs/libvpx/build/make/configure.sh \
      --replace AS=\''${AS} AS=yasm

    # Disable advertisement banners
    for f in src/include/cc.h libs/esl/src/include/cc.h; do
      {
        echo 'const char *cc = "";'
        echo 'const char *cc_s = "";'
      } > $f
    done
  '';

  nativeBuildInputs = [ pkg-config autoreconfHook ];
  buildInputs = [
    openssl ncurses gnutls readline perl libjpeg
    sqlite pcre speex ldns libedit yasm which
    libsndfile libtiff
    libuuid
  ]
  ++ lib.unique (lib.concatMap (mod: mod.inputs) enabledModules)
  ++ lib.optionals stdenv.isDarwin [ SystemConfiguration ];

  enableParallelBuilding = true;

  NIX_CFLAGS_COMPILE = "-Wno-error";

  hardeningDisable = [ "format" ];

  preConfigure = ''
    ./bootstrap.sh
    cp "${modulesConf}" modules.conf
  '';

  postInstall = ''
    # helper for compiling modules... not generally useful; also pulls in perl dependency
    rm "$out"/bin/fsxs
    # include configuration templates
    cp -r conf $out/share/freeswitch/
  '';

  passthru.tests.freeswitch = nixosTests.freeswitch;

  meta = {
    description = "Cross-Platform Scalable FREE Multi-Protocol Soft Switch";
    homepage = "https://freeswitch.org/";
    license = lib.licenses.mpl11;
    maintainers = with lib.maintainers; [ misuzu ];
    platforms = with lib.platforms; unix;
  };
}
