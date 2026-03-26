{
  description = "ChampSim - a trace-driven simulator for microarchitecture research";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Nix-native replacements for vcpkg dependencies:
        #   cli11, nlohmann-json, fmt, bzip2, liblzma, zlib, catch2
        nativeDeps = with pkgs; [
          cli11
          nlohmann_json
          fmt
          bzip2
          xz          # provides liblzma
          zlib
          catch2_3
        ];

        buildTools = with pkgs; [
          gcc
          gnumake
          python3
          pkg-config
        ];

      in
      {
        # ---------------------------------------------------------------------------
        # `nix develop` — dev shell with all dependencies.
        #
        # Usage (from project root):
        #   nix develop
        #   ./config.sh champsim_config.json
        #   make
        # ---------------------------------------------------------------------------
        devShells.default = pkgs.mkShell {
          name = "champsim-dev";

          packages = buildTools ++ nativeDeps;

          shellHook = ''
            echo "ChampSim dev environment ready."
            echo ""
            echo "Build steps:"
            echo "  ./config.sh champsim_config.json   # generate Makefile config"
            echo "  make                               # compile"
            echo ""

            # Expose Nix-provided headers/libs via compiler env vars so the
            # Makefile's -lCLI11 -llzma -lz -lbz2 -lfmt flags resolve correctly.
            export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE \
              -isystem ${pkgs.cli11}/include \
              -isystem ${pkgs.nlohmann_json}/include \
              -isystem ${pkgs.fmt}/include \
              -isystem ${pkgs.catch2_3}/include"

            export NIX_LDFLAGS="$NIX_LDFLAGS \
              -L${pkgs.fmt}/lib \
              -L${pkgs.bzip2}/lib \
              -L${pkgs.xz}/lib \
              -L${pkgs.zlib}/lib"

            # Synthesise a fake vcpkg triplet directory so the Makefile's
            # TRIPLET_DIR glob finds something (it scans vcpkg_installed/*/
            # and picks the first non-vcpkg/ directory).
            if [ ! -d vcpkg_installed/nix-triplet ]; then
              mkdir -p vcpkg_installed/nix-triplet/include
              mkdir -p vcpkg_installed/nix-triplet/lib/manual-link

              ln -sfn ${pkgs.cli11}/include/CLI             vcpkg_installed/nix-triplet/include/CLI
              ln -sfn ${pkgs.nlohmann_json}/include/nlohmann vcpkg_installed/nix-triplet/include/nlohmann
              ln -sfn ${pkgs.fmt}/include/fmt               vcpkg_installed/nix-triplet/include/fmt
              ln -sfn ${pkgs.catch2_3}/include/catch2       vcpkg_installed/nix-triplet/include/catch2

              # CLI11 is header-only; create an empty archive so -lCLI11 links.
              ar rcs vcpkg_installed/nix-triplet/lib/libCLI11.a
            fi
          '';
        };

        # ---------------------------------------------------------------------------
        # `nix build` — build the simulator, output at result/bin/champsim.
        # ---------------------------------------------------------------------------
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "champsim";
          version = "1.0";

          src = ./.;

          nativeBuildInputs = buildTools;
          buildInputs = nativeDeps;

          preConfigure = ''
            # Synthesise a fake vcpkg triplet directory so the Makefile's
            # TRIPLET_DIR detection finds something.
            mkdir -p vcpkg_installed/nix-triplet/include
            mkdir -p vcpkg_installed/nix-triplet/lib/manual-link

            ln -sfn ${pkgs.cli11}/include/CLI             vcpkg_installed/nix-triplet/include/CLI
            ln -sfn ${pkgs.nlohmann_json}/include/nlohmann vcpkg_installed/nix-triplet/include/nlohmann
            ln -sfn ${pkgs.fmt}/include/fmt               vcpkg_installed/nix-triplet/include/fmt
            ln -sfn ${pkgs.catch2_3}/include/catch2       vcpkg_installed/nix-triplet/include/catch2

            # CLI11 is header-only so there is no libCLI11.a in the Nix store,
            # but the Makefile hard-codes "override LDLIBS += -lCLI11" (with
            # 'override', so we cannot suppress it from the command line).
            # Create an empty archive to satisfy the linker.
            ar rcs vcpkg_installed/nix-triplet/lib/libCLI11.a
          '';

          configurePhase = ''
            runHook preConfigure
            python3 config.sh champsim_config.json
            runHook postConfigure
          '';

          buildPhase = ''
            make -j$(nproc) \
              CPPFLAGS="-I.csconfig \
                        -isystem vcpkg_installed/nix-triplet/include \
                        -isystem ${pkgs.cli11}/include \
                        -isystem ${pkgs.nlohmann_json}/include \
                        -isystem ${pkgs.fmt}/include \
                        -isystem ${pkgs.catch2_3}/include" \
              LDFLAGS="-L${pkgs.fmt}/lib \
                       -L${pkgs.bzip2}/lib \
                       -L${pkgs.xz}/lib \
                       -L${pkgs.zlib}/lib" \
              LDLIBS="-llzma -lz -lbz2 -lfmt"
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp bin/champsim $out/bin/
          '';

          meta = {
            description = "ChampSim trace-based microarchitecture simulator";
            homepage = "https://github.com/ChampSim/ChampSim";
            license = pkgs.lib.licenses.asl20;
          };
        };
      }
    );
}
