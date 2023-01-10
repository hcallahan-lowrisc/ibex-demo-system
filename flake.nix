{
  description = "Environment for synthesizing and simulating the ibex-demo-system.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    deps = {
      url = "path:./dependencies";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = all@{ self, nixpkgs, flake-utils, deps, ... }:

    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = { allowUnfree = true; };
          overlays =
            [ # Add extra packages we might need
              # Currently this contains the lowrisc riscv-toolchain, and spike
              deps.overlay_pkgs
              # Add all the python packages we need that aren't in nixpkgs
              # (See the ./dependencies folder for more info)
              (final: prev: {
                python3 = prev.python3.override {
                  packageOverrides = deps.overlay_python;
                };
              })
              # Add some missing dependencies to nixpkgs#verilator
              (final: prev: {
                verilator = prev.verilator.overrideAttrs ( oldAttrs : {
                  propagatedBuildInputs = [ final.zlib final.libelf ];
                });
              })
            ];
        };

        pythonEnv = pkgs.python3.withPackages(ps: with ps; [ pip fusesoc edalize pyyaml Mako ]);
        # Currently we don't build the riscv-toolchain from src, we use a github release
        # (See ./dependencies/riscv-gcc-toolchain-lowrisc.nix)
        # riscv-gcc-toolchain-lowrisc-src = pkgs.callPackage \
        #   ./dependencies/riscv_gcc.nix {
        #     riscv-arch = "rv32imc";
        #   };

        # Using requireFile prevents rehashing each time.
        # This saves much seconds during rebuilds.
        src = pkgs.requireFile rec {
          name = "vivado_bundled.tar.gz";
          sha256 = "1yxx6crvawhzvary9js0m8bzm35vv6pzfqdkv095r84lb13fyp7b";
          # Print the following message if the name / hash are not
          # found in the store.
          message = ''
            requireFile :
            file/dir not found in /nix/store
            file = ${name}
            hash = ${sha256}

            This nix expression requires that ${name} is already part of the store.
            - Login to xilinx.com
            - Download Unified Installer from https://www.xilinx.com/support/download.html,
            - Run installer, specify a 'Download Image (Install Seperately)'
            - Gzip the bundled installed image directory
            - Rename the file to ${name}
            - Add it to the nix store with
              $ nix-prefetch-url --type sha256 file:</path/to/${name}>
          '';
        };

        vivado = pkgs.callPackage (import ./vivado.nix) {
          # We need to prepare the pre-downloaded installer to
          # execute within a nix build. Make use of the included java deps,
          # but we still need to do a little patching to make it work.
          vivado-src = pkgs.stdenv.mkDerivation rec {
            pname = "vivado_src";
            version = "2022.2";
            inherit src;
            postPatch = ''
              patchShebangs .
              patchelf \
                --set-interpreter $(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker) \
                tps/lnx64/jre*/bin/java
            '';
            dontBuild = true; dontFixup = true;
            installPhase = ''
              mkdir -p $out
              cp -R * $out
            '';
          };
        };

        # This is the final list of dependencies we need to build the project.
        project_deps = [
          vivado
          pythonEnv
        ] ++ (with pkgs; [
          cmake
          openocd
          screen
          verilator
          riscv-gcc-toolchain-lowrisc
          gtkwave
          srecord
        ]);

      in {
        packages.dockertest = pkgs.dockerTools.buildImage {
          name = "hello-docker";
          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = [ pkgs.coreutils
                      pkgs.sl ];
          };
          config = {
            Cmd = [ "${pkgs.sl}/bin/sl" ];
          };
        };
        devShells.labenv = pkgs.mkShell {
          name = "labenv";
          buildInputs = project_deps;
          shellHook = ''
            # FIXME This works on Ubuntu, may not on other distros. FIXME
            export LOCALE_ARCHIVE=/usr/lib/locale/locale-archive

            # HACK fixup some paths to use our sandboxed python environment
            # Currently, fusesoc tries to invoke the program 'python3' from the
            # PATH, which when running under a nix python environment, resolves
            # to the raw python binary, not wrapped and not including the
            # environment's packages. Hence, the first time an import is evaluated
            # we will error out.
            sed -i -- \
              's|interpreter:.*|interpreter: ${pythonEnv}/bin/python3|g' \
              vendor/lowrisc_ibex/vendor/lowrisc_ip/dv/tools/ralgen/ralgen.core
            sed -i -- \
              's|interpreter:.*|interpreter: ${pythonEnv}/bin/python3|g' \
              vendor/lowrisc_ibex/vendor/lowrisc_ip/ip/prim/primgen.core

            echo "Welcome the the ibex-demo-system nix environment!"
            echo "-------------------------------------------------"

            cat << EOF
            Build ibex software :
                mkdir sw/build && pushd sw/build && cmake ../ && make && popd
            Build ibex simulation verilator model :
                fusesoc --cores-root=. run --target=sim --tool=verilator --setup --build lowrisc:ibex:demo_system
            Run ibex simulator verilator model :
                ./build/lowrisc_ibex_demo_system_0/sim-verilator/Vibex_demo_system [-t] \\
                  --meminit=ram,sw/build/demo/hello_world/demo
            Build ibex-demo-system FPGA bitstream for Arty-A7 :
                fusesoc --cores-root=. run --target=synth --setup --build lowrisc:ibex:demo_system
            Program Arty-A7 FPGA with bitstream :
                fusesoc --cores-root=. run --target=synth --run lowrisc:ibex:demo_system
              OR
                make -C ./build/lowrisc_ibex_demo_system_0/synth-vivado/ pgm
            Load ibex software to the programmed FPGA :
                ./util/load_demo_system.sh run ./sw/build/demo/lcd_st7735/lcd_st7735
            EOF
          '';
        };
      })
    ) // {

      overlay = final: prev: { };
      overlays = { exampleOverlay = self.overlay; };

    # Utilized by `nix run .#<name>`
    # apps.x86_64-linux.hello = {
    #   type = "app";
    #   program = c-hello.packages.x86_64-linux.hello;
    # };

    # Utilized by `nix run . -- <args?>`
    # defaultApp.x86_64-linux = self.apps.x86_64-linux.hello;
  };
}
