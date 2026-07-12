{
  description = "Dependency-light Common Lisp CLI toolkit";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
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
