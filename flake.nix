# flake.nix
{
  description = "Manyfold - 3D Model Management Application";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            ruby_3_2
            bundler
            nodejs-18_x
            yarn
            foreman
            libarchive
            sqlite
            redis # For development Sidekiq
            # Development tools
            rubocop
            # Required for i18n tasks
            gettext
            # Required for asset compilation
            nodePackages.typescript
            # Additional build dependencies
            pkg-config
            # Libraries needed for gems
            readline
            openssl
            zlib
            libyaml
            # Required for Mittsu (THREE.js port)
            libGL
            libGLU
            xorg.libX11
            xorg.libXext
            xorg.libXcursor
            xorg.libXrandr
            xorg.libXinerama
            xorg.libXi
            xorg.libXxf86vm
          ];

          shellHook = ''
            export LANG=en_US.UTF-8
            export BUNDLE_PATH=vendor/bundle
            export DATABASE_URL="sqlite3:db/development.sqlite3"
            export PATH="$PWD/bin:$PATH"
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [
              pkgs.libGL
              pkgs.libGLU
              pkgs.xorg.libX11
              pkgs.xorg.libXext
              pkgs.xorg.libXcursor
              pkgs.xorg.libXrandr
              pkgs.xorg.libXinerama
              pkgs.xorg.libXi
              pkgs.xorg.libXxf86vm
            ]}"
            
            # Initialize database directory if it doesn't exist
            mkdir -p db

            # Load environment variables from .env if it exists
            if [ -f .env ]; then
              source .env
            fi

            # Print setup instructions
            echo "Manyfold development environment ready!"
            echo "Run 'bundle install' to install Ruby dependencies including Guard"
            echo "Run 'bin/dev' to start the application"
            echo "The application will be available at http://127.0.0.1:5000"
          '';
        };

        # Production package definition
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "manyfold";
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = with pkgs; [
            pkg-config
            nodePackages.typescript
          ];

          buildInputs = with pkgs; [
            ruby_3_2
            bundler
            nodejs-18_x
            yarn
            postgresql
            libarchive
            # Required for Mittsu
            libGL
            libGLU
            xorg.libX11
            xorg.libXext
            xorg.libXcursor
            xorg.libXrandr
            xorg.libXinerama
            xorg.libXi
            xorg.libXxf86vm
          ];

          buildPhase = ''
            export HOME=$PWD
            export BUNDLE_PATH=vendor/bundle
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [
              pkgs.libGL
              pkgs.libGLU
              pkgs.xorg.libX11
              pkgs.xorg.libXext
              pkgs.xorg.libXcursor
              pkgs.xorg.libXrandr
              pkgs.xorg.libXinerama
              pkgs.xorg.libXi
              pkgs.xorg.libXxf86vm
            ]}"
            
            # Install dependencies
            bundle config set --local without 'development test'
            bundle install
            yarn install --production
            
            # Compile assets and translations
            bundle exec i18n export -c config/i18n-js.yml
            bundle exec rails assets:precompile RAILS_ENV=production
          '';

          installPhase = ''
            mkdir -p $out/share/manyfold
            cp -r . $out/share/manyfold
          '';
        };
      });
}
