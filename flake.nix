{
  description = "Dependency-light Common Lisp CLI toolkit";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    cl-weave = {
      url = "github:takeokunn/cl-weave";
      flake = false;
    };
    cl-prolog = {
      url = "github:takeokunn/cl-prolog";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, cl-weave, cl-prolog }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      clWeaveSourceDir = cl-weave.outPath;
      clPrologSourceDir = cl-prolog.outPath;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.sbcl
              pkgs.rlwrap
            ];
            CL_WEAVE_SOURCE_DIR = clWeaveSourceDir;
            CL_PROLOG_SOURCE_DIR = clPrologSourceDir;
          };
        });

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          makeLispCheck = implementation: package:
            pkgs.runCommand "cl-cli-tests-${implementation}"
              {
                nativeBuildInputs = [ package ];
                src = self;
                CL_WEAVE_SOURCE_DIR = clWeaveSourceDir;
                CL_PROLOG_SOURCE_DIR = clPrologSourceDir;
              }
              ''
                cp -R "$src" source
                chmod -R u+w source
                cd source
                export HOME="$TMPDIR/home"
                export XDG_CACHE_HOME="$TMPDIR/cache"
                mkdir -p "$HOME" "$XDG_CACHE_HOME"
                ${implementation} --norc --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)'
                touch "$out"
              '';
          sbcl-check = pkgs.runCommand "cl-cli-tests-sbcl"
            {
              nativeBuildInputs = [ pkgs.sbcl ];
              src = self;
              CL_WEAVE_SOURCE_DIR = clWeaveSourceDir;
              CL_PROLOG_SOURCE_DIR = clPrologSourceDir;
            }
            ''
              cp -R "$src" source
              chmod -R u+w source
              cd source
              export HOME="$TMPDIR/home"
              export XDG_CACHE_HOME="$TMPDIR/cache"
              mkdir -p "$HOME" "$XDG_CACHE_HOME"
              sbcl --non-interactive --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)' --quit
              touch "$out"
            '';
          ecl-check = makeLispCheck "ecl" pkgs.ecl;
        in
        {
          sbcl = sbcl-check;
          ecl = ecl-check;
          default = pkgs.runCommand "cl-cli-checks" {} ''
            mkdir -p "$out"
            ln -s ${sbcl-check} "$out/sbcl"
            ln -s ${ecl-check} "$out/ecl"
          '';
        });
    };
}
