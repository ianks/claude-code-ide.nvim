t inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs = { self, nixpkgs, flake-utils, treefmt-nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # treefmt configuration
        treefmtEval = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs = {
            # Lua formatting with stylua
            stylua = {
              enable = true;
            };

            # Nix formatting
            nixpkgs-fmt.enable = true;

            # Markdown formatting
            mdformat = {
              enable = true;
            };

            # YAML formatting
            yamlfmt = {
              enable = true;
            };
          };
        };
      in
      {
        # Formatter
        formatter = treefmtEval.config.build.wrapper;

        # Development shell
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            # Neovim for testing
            neovim

            # Lua development
            lua
            luajit
            luarocks

            # Formatters (also available via treefmt)
            stylua
            nixpkgs-fmt
            mdformat
            yamlfmt

            # Testing tools
            luajitPackages.busted
            luajitPackages.luacheck

            # Development tools
            just
            ripgrep
            fd
            git

            # Language servers
            lua-language-server
            nil # Nix LSP

            # treefmt
            treefmtEval.config.build.wrapper
          ];

          shellHook = ''
            echo "🚀 claude-code-ide.nvim development environment"
            echo ""
            echo "Available commands:"
            echo "  just         - Run project tasks"
            echo "  just test    - Run all tests"
            echo "  treefmt      - Format all files"
            echo "  luacheck .   - Lint Lua files"
            echo ""
          '';
        };

        # Check that runs treefmt
        checks = {
          formatting = treefmtEval.config.build.check self;
        };
      });
}
