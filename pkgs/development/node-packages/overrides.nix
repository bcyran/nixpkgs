# Do not use overrides in this file to add  `meta.mainProgram` to packages. Use `./main-programs.nix`
# instead.
{ pkgs, nodejs }:

let
  inherit (pkgs)
    stdenv
    lib
    callPackage
    fetchFromGitHub
    fetchurl
    fetchpatch
    nixosTests;

  since = version: lib.versionAtLeast nodejs.version version;
  before = version: lib.versionOlder nodejs.version version;
in

final: prev: {
  inherit nodejs;

  "@angular/cli" = prev."@angular/cli".override {
    prePatch = ''
      export NG_CLI_ANALYTICS=false
    '';
    nativeBuildInputs = [ pkgs.installShellFiles ];
    postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    for shell in bash zsh; do
      installShellCompletion --cmd ng \
        --$shell <($out/bin/ng completion script)
    done
    '';
  };

  "@electron-forge/cli" = prev."@electron-forge/cli".override {
    buildInputs = [ final.node-gyp-build ];
  };

  fast-cli = prev.fast-cli.override {
    nativeBuildInputs = [ pkgs.buildPackages.makeWrapper ];
    prePatch = ''
      export PUPPETEER_SKIP_DOWNLOAD=1
    '';
    postInstall = ''
      wrapProgram $out/bin/fast \
        --set PUPPETEER_EXECUTABLE_PATH ${pkgs.chromium.outPath}/bin/chromium
    '';
  };

  fauna-shell = prev.fauna-shell.override {
    # printReleaseNotes just pulls them from GitHub which is not allowed in sandbox
    preRebuild = ''
      sed -i 's|"node ./tools/printReleaseNotes"|"true"|' node_modules/faunadb/package.json
    '';
  };

  ijavascript = prev.ijavascript.override (oldAttrs: {
    preRebuild = ''
      export npm_config_zmq_external=true
    '';
    buildInputs = oldAttrs.buildInputs ++ [ final.node-gyp-build pkgs.zeromq ];
  });

  joplin = prev.joplin.override (oldAttrs:{
    nativeBuildInputs = [
      pkgs.pkg-config
      (pkgs.python3.withPackages (ps: [ ps.setuptools ]))
    ] ++ lib.optionals stdenv.hostPlatform.isDarwin [
      pkgs.xcbuild
    ];
    buildInputs = with pkgs; [
      # required by sharp
      # https://sharp.pixelplumbing.com/install
      vips

      libsecret
      final.node-gyp-build
      node-pre-gyp

      pixman
      cairo
      pango
    ] ++ lib.optionals stdenv.hostPlatform.isDarwin [
      darwin.apple_sdk.frameworks.AppKit
      darwin.apple_sdk.frameworks.Security
    ];

    # add newer node-addon-api to build sharp
    # https://github.com/lovell/sharp/issues/3920
    dependencies = [
      {
        name = "node-addon-api";
        packageName = "node-addon-api";
        version = "7.1.0";
        src = fetchurl {
          url = "https://registry.npmjs.org/node-addon-api/-/node-addon-api-7.1.0.tgz";
          sha512 = "mNcltoe1R8o7STTegSOHdnJNN7s5EUvhoS7ShnTHDyOSd+8H+UdWODq6qSv67PjC8Zc5JRT8+oLAMCr0SIXw7g==";
        };
      }
    ] ++ oldAttrs.dependencies;

    meta = oldAttrs.meta // {
      # ModuleNotFoundError: No module named 'distutils'
      broken = stdenv.hostPlatform.isDarwin; # still broken on darwin
    };
  });

  jsonplaceholder = prev.jsonplaceholder.override {
    buildInputs = [ nodejs ];
    postInstall = ''
      exe=$out/bin/jsonplaceholder
      mkdir -p $out/bin
      cat >$exe <<EOF
      #!${pkgs.runtimeShell}
      exec -a jsonplaceholder ${nodejs}/bin/node $out/lib/node_modules/jsonplaceholder/index.js
      EOF
      chmod a+x $exe
    '';
  };

  keyoxide = prev.keyoxide.override {
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = with pkgs; [
      pixman
      cairo
      pango
    ] ++ lib.optionals stdenv.hostPlatform.isDarwin [
      darwin.apple_sdk.frameworks.CoreText
    ];
  };

  makam =  prev.makam.override {
    nativeBuildInputs = [ pkgs.buildPackages.makeWrapper ];
    postFixup = ''
      wrapProgram "$out/bin/makam" --prefix PATH : ${lib.makeBinPath [ nodejs ]}
      ${lib.optionalString stdenv.hostPlatform.isLinux "patchelf --set-interpreter ${stdenv.cc.libc}/lib/ld-linux-x86-64.so.2 \"$out/lib/node_modules/makam/makam-bin-linux64\""}
    '';
  };

  node2nix = prev.node2nix.override {
    # Get latest commit for misc fixes
    src = fetchFromGitHub {
      owner = "svanderburg";
      repo = "node2nix";
      rev = "315e1b85a6761152f57a41ccea5e2570981ec670";
      sha256 = "sha256-8OxTOkwBPcnjyhXhxQEDd8tiaQoHt91zUJX5Ka+IXco=";
    };
    nativeBuildInputs = [ pkgs.buildPackages.makeWrapper ];
    postInstall = let
      patches = [
        # Needed to fix packages with DOS line-endings after above patch - PR svanderburg/node2nix#314
        (fetchpatch {
          name = "convert-crlf-for-script-bin-files.patch";
          url = "https://github.com/svanderburg/node2nix/commit/91aa511fe7107938b0409a02ab8c457a6de2d8ca.patch";
          hash = "sha256-ISiKYkur/o8enKDzJ8mQndkkSC4yrTNlheqyH+LiXlU=";
        })
        # fix nodejs attr names
        (fetchpatch {
          url = "https://github.com/svanderburg/node2nix/commit/3b63e735458947ef39aca247923f8775633363e5.patch";
          hash = "sha256-pe8Xm4mjPh9oKXugoMY6pRl8YYgtdw0sRXN+TienalU=";
        })
        # Use top-level cctools in generated files - PR svanderburg/node2nix#334
        (fetchpatch {
          url = "https://github.com/svanderburg/node2nix/commit/31c308bba5f39ea0105f66b9f40dbe57fed7a292.patch";
          hash = "sha256-DdNRteonMvyffPh0uo0lUbsohKYnyqv0QcD9vjN6aXE=";
        })
      ];
    in ''
      ${lib.concatStringsSep "\n" (map (patch: "patch -d $out/lib/node_modules/node2nix -p1 < ${patch}") patches)}
      wrapProgram "$out/bin/node2nix" --prefix PATH : ${lib.makeBinPath [ pkgs.nix ]}
    '';
  };

  postcss-cli = prev.postcss-cli.override (oldAttrs: let
    esbuild-version = (lib.findFirst (dep: dep.name == "esbuild") null oldAttrs.dependencies).version;
    esbuild-linux-x64 = {
      name = "_at_esbuild_slash_esbuild-linux-x64";
      packageName = "@esbuild/linux-x64";
      version = esbuild-version;
      src = fetchurl {
        url = "https://registry.npmjs.org/@esbuild/linux-x64/-/linux-x64-${esbuild-version}.tgz";
        sha512 = "sha512-9yl91rHw/cpwMCNytUDxwj2XjFpxML0y9HAOH9pNVQDpQrBxHy01Dx+vaMu0N1CKa/RzBD2hB4u//nfc+Sd3Cw==";
      };
    };
    esbuild-linux-arm64 = {
      name = "_at_esbuild_slash_esbuild-linux-arm64";
      packageName = "@esbuild/linux-arm64";
      version = esbuild-version;
      src = fetchurl {
        url = "https://registry.npmjs.org/@esbuild/linux-arm64/-/linux-arm64-${esbuild-version}.tgz";
        sha512 = "sha512-9QAQjTWNDM/Vk2bgBl17yWuZxZNQIF0OUUuPZRKoDtqF2k4EtYbpyiG5/Dk7nqeK6kIJWPYldkOcBqjXjrUlmg==";
      };
    };
    esbuild-darwin-x64 = {
      name = "_at_esbuild_slash_esbuild-darwin-x64";
      packageName = "@esbuild/darwin-x64";
      version = esbuild-version;
      src = fetchurl {
        url = "https://registry.npmjs.org/@esbuild/darwin-x64/-/darwin-x64-${esbuild-version}.tgz";
        sha512 = "sha512-DgDaYsPWFTS4S3nWpFcMn/33ZZwAAeAFKNHNa1QN0rI4pUjgqf0f7ONmXf6d22tqTY+H9FNdgeaAa+YIFUn2Rg==";
      };
    };
    esbuild-darwin-arm64 = {
      name = "_at_esbuild_slash_esbuild-darwin-arm64";
      packageName = "@esbuild/darwin-arm64";
      version = esbuild-version;
      src = fetchurl {
        url = "https://registry.npmjs.org/@esbuild/darwin-arm64/-/darwin-arm64-${esbuild-version}.tgz";
        sha512 = "sha512-mVwdUb5SRkPayVadIOI78K7aAnPamoeFR2bT5nszFUZ9P8UpK4ratOdYbZZXYSqPKMHfS1wdHCJk1P1EZpRdvw==";
      };
    };
  in{
    nativeBuildInputs = [ pkgs.buildPackages.makeWrapper ];
    dependencies = oldAttrs.dependencies
      ++ lib.optional (stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64) esbuild-linux-x64
      ++ lib.optional (stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isAarch64) esbuild-linux-arm64
      ++ lib.optional (stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isx86_64) esbuild-darwin-x64
      ++ lib.optional (stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64) esbuild-darwin-arm64;
    postInstall = ''
      wrapProgram "$out/bin/postcss" \
        --prefix NODE_PATH : ${final.postcss}/lib/node_modules \
        --prefix NODE_PATH : ${pkgs.autoprefixer}/node_modules
      ln -s '${final.postcss}/lib/node_modules/postcss' "$out/lib/node_modules/postcss"
    '';
    passthru.tests = {
      simple-execution = callPackage ./package-tests/postcss-cli.nix {
        inherit (final) postcss-cli;
      };
    };
    meta = oldAttrs.meta // {
      maintainers = with lib.maintainers; [ Luflosi ];
      license = lib.licenses.mit;
    };
  });

  pulp = prev.pulp.override {
    # tries to install purescript
    npmFlags = builtins.toString [ "--ignore-scripts" ];

    nativeBuildInputs = [ pkgs.buildPackages.makeWrapper ];
    postInstall =  ''
      wrapProgram "$out/bin/pulp" --suffix PATH : ${lib.makeBinPath [
        pkgs.purescript
      ]}
    '';
  };

  rush = prev."@microsoft/rush".override {
    name = "rush";
  };

  thelounge-plugin-closepms = prev.thelounge-plugin-closepms.override {
    nativeBuildInputs = [ pkgs.node-pre-gyp ];
  };

  thelounge-plugin-giphy = prev.thelounge-plugin-giphy.override {
    nativeBuildInputs = [ pkgs.node-pre-gyp ];
  };

  thelounge-theme-flat-blue = prev.thelounge-theme-flat-blue.override {
    nativeBuildInputs = [ pkgs.node-pre-gyp ];
    # TODO: needed until upstream pins thelounge version 4.3.1+ (which fixes dependency on old sqlite3 and transitively very old node-gyp 3.x)
    preRebuild = ''
      rm -r node_modules/node-gyp
    '';
  };

  thelounge-theme-flat-dark = prev.thelounge-theme-flat-dark.override {
    nativeBuildInputs = [ pkgs.node-pre-gyp ];
    # TODO: needed until upstream pins thelounge version 4.3.1+ (which fixes dependency on old sqlite3 and transitively very old node-gyp 3.x)
    preRebuild = ''
      rm -r node_modules/node-gyp
    '';
  };

  ts-node = prev.ts-node.override {
    nativeBuildInputs = [ pkgs.buildPackages.makeWrapper ];
    postInstall = ''
      wrapProgram "$out/bin/ts-node" \
      --prefix NODE_PATH : ${pkgs.typescript}/lib/node_modules
    '';
  };

  tsun = prev.tsun.override {
    nativeBuildInputs = [ pkgs.buildPackages.makeWrapper ];
    postInstall = ''
      wrapProgram "$out/bin/tsun" \
      --prefix NODE_PATH : ${pkgs.typescript}/lib/node_modules
    '';
  };

  uppy-companion = prev."@uppy/companion".override {
    name = "uppy-companion";
  };

  vega-cli = prev.vega-cli.override {
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = with pkgs; [
      node-pre-gyp
      pixman
      cairo
      pango
      libjpeg
    ] ++ lib.optionals stdenv.hostPlatform.isDarwin [
      darwin.apple_sdk.frameworks.CoreText
    ];
  };

  vega-lite = prev.vega-lite.override {
      postInstall = ''
        cd node_modules
        for dep in ${final.vega-cli}/lib/node_modules/vega-cli/node_modules/*; do
          if [[ ! -d ''${dep##*/} ]]; then
            ln -s "${final.vega-cli}/lib/node_modules/vega-cli/node_modules/''${dep##*/}"
          fi
        done
      '';
      passthru.tests = {
        simple-execution = callPackage ./package-tests/vega-lite.nix {
          inherit (final) vega-lite;
        };
      };
  };

  wavedrom-cli = prev.wavedrom-cli.override {
    nativeBuildInputs = [ pkgs.pkg-config pkgs.node-pre-gyp ];
    # These dependencies are required by
    # https://github.com/Automattic/node-canvas.
    buildInputs = with pkgs; [
      giflib
      pixman
      cairo
      pango
    ] ++ lib.optionals stdenv.hostPlatform.isDarwin [
      darwin.apple_sdk.frameworks.CoreText
    ];
  };
}
