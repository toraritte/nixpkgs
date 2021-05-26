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
  # defaultModules :: 
  defaultModules =
    mods:
         [ mods.applications.commands
           mods.applications.conference
           mods.applications.db
           mods.applications.dptools
           mods.applications.enum
           mods.applications.esf
           mods.applications.expr
           mods.applications.fifo
           mods.applications.fsv
           mods.applications.hash
           mods.applications.httapi
           mods.applications.sms
           mods.applications.spandsp
           mods.applications.valet_parking
           mods.applications.voicemail
           mods.applications.curl

           mods.codecs.amr
           mods.codecs.b64
           mods.codecs.g723_1
           mods.codecs.g729
           mods.codecs.h26x
           mods.codecs.opus

           mods.databases.mariadb
           mods.databases.pgsql

           mods.dialplans.asterisk
           mods.dialplans.xml

           mods.endpoints.loopback
           mods.endpoints.rtc
           mods.endpoints.skinny
           mods.endpoints.sofia
           mods.endpoints.verto

           mods.event_handlers.cdr_csv
           mods.event_handlers.cdr_sqlite
           mods.event_handlers.event_socket

           mods.formats.local_stream
           mods.formats.native_file
           mods.formats.png
           mods.formats.sndfile
           mods.formats.tone_stream

           mods.languages.lua

           mods.loggers.console
           mods.loggers.logfile
           mods.loggers.syslog

           mods.say.en

           mods.xml_int.cdr
           mods.xml_int.rpc
           mods.xml_int.scgi
         ]
      ++ lib.optionals stdenv.isLinux [ mods.endpoints.gsmopen ]
  ;

  enabledModules = (if modules != null then modules else defaultModules) availableModules;

  modulesConf = let
    lst = builtins.map (mod: mod.path) enabledModules;
    str = lib.strings.concatStringsSep "\n" lst;
    in builtins.toFile "modules.conf" str;

in

stdenv.mkDerivation rec {
  pname = "freeswitch";
  version = "1.10.6";
  src = fetchFromGitHub {
    owner = "signalwire";
    repo = pname;
    rev = "v${version}";
    sha256 = "1i5n06pds3kvzhhzfwvhwxnvcb2p2fcr8k52157aplm2i7prl4q2";
  };

  # COMMENT: this is fixed in 1.10.6, but keeping for future reference
  #          (will definitely be needed when adding playback speed pitch fix)
  # patches = [
  #   # https://github.com/signalwire/freeswitch/pull/812 fix mod_spandsp, mod_gsmopen build, drop when updating from 1.10.5
  #   (fetchpatch {
  #     url = "https://github.com/signalwire/freeswitch/commit/51fba83ed3ed2d9753d8e6b13e13001aca50b493.patch";
  #     sha256 = "0h2bmifsyyasxjka3pczbmqym1chvz91fmb589njrdbwpkjyvqh3";
  #   })
  # ];

  postPatch = ''
    #########################################################################
    # Needed, even though libvpx is a video codec, because                  #
    # it is in FreeSWITCH core; won't compile otherwise                     #
    # https://freeswitch.org/confluence/display/FREESWITCH/Debian+8+Jessie  #
    #########################################################################

    patchShebangs     libs/libvpx/build/make/rtcd.pl
    substituteInPlace \
      libs/libvpx/build/make/configure.sh \
      --replace AS=\''${AS} AS=yasm

    #########################################################################
    # To disable advertisement banners, uncomment the lines below           #
    #########################################################################

    # for f in src/include/cc.h libs/esl/src/include/cc.h; do
    #   {
    #     echo 'const char *cc = "";'
    #     echo 'const char *cc_s = "";'
    #   } > $f
    # done
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
