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
            guard
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

# configuration.nix module for the service
{ config, lib, pkgs, ... }:

{
  imports = [ ];

  options.services.manyfold = with lib; {
    enable = mkEnableOption "Manyfold service";
    
    port = mkOption {
      type = types.port;
      default = 5000;
      description = "Port to listen on";
    };

    environment = mkOption {
      type = types.attrs;
      default = {};
      description = "Environment variables for the application";
    };

    redisUrl = mkOption {
      type = types.str;
      default = "redis://localhost:6379/1";
      description = "Redis URL for Sidekiq";
    };

    uploadsPath = mkOption {
      type = types.str;
      default = "/var/lib/manyfold/uploads";
      description = "Path for file uploads";
    };
  };

  config = lib.mkIf config.services.manyfold.enable {
    # Enable required services
    services.postgresql = {
      enable = true;
      ensureUsers = [{
        name = "manyfold";
        ensurePermissions = {
          "DATABASE manyfold_production" = "ALL PRIVILEGES";
        };
      }];
      ensureDatabases = [ "manyfold_production" ];
    };

    services.redis.servers."manyfold" = {
      enable = true;
      port = 6379;
    };

    # Main application service
    systemd.services.manyfold = {
      description = "Manyfold Application";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "postgresql.service" "redis-manyfold.service" ];
      
      environment = {
        RAILS_ENV = "production";
        PORT = toString config.services.manyfold.port;
        DATABASE_URL = "postgresql:///manyfold_production?host=/run/postgresql";
        REDIS_URL = config.services.manyfold.redisUrl;
        UPLOADS_PATH = config.services.manyfold.uploadsPath;
      } // config.services.manyfold.environment;

      serviceConfig = {
        Type = "simple";
        User = "manyfold";
        Group = "manyfold";
        WorkingDirectory = "${pkgs.manyfold}/share/manyfold";
        ExecStart = "${pkgs.ruby_3_2}/bin/bundle exec rails server";
        Restart = "always";
        # Required for Mittsu
        Environment = "LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath [
          pkgs.libGL
          pkgs.libGLU
          pkgs.xorg.libX11
          pkgs.xorg.libXext
          pkgs.xorg.libXcursor
          pkgs.xorg.libXrandr
          pkgs.xorg.libXinerama
          pkgs.xorg.libXi
          pkgs.xorg.libXxf86vm
        ]}";
      };
    };

    # Sidekiq service for background jobs
    systemd.services.manyfold-sidekiq = {
      description = "Manyfold Sidekiq Worker";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "postgresql.service" "redis-manyfold.service" ];
      
      environment = {
        RAILS_ENV = "production";
        DATABASE_URL = "postgresql:///manyfold_production?host=/run/postgresql";
        REDIS_URL = config.services.manyfold.redisUrl;
        UPLOADS_PATH = config.services.manyfold.uploadsPath;
      } // config.services.manyfold.environment;

      serviceConfig = {
        Type = "simple";
        User = "manyfold";
        Group = "manyfold";
        WorkingDirectory = "${pkgs.manyfold}/share/manyfold";
        ExecStart = "${pkgs.ruby_3_2}/bin/bundle exec sidekiq";
        Restart = "always";
        Environment = "LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath [
          pkgs.libGL
          pkgs.libGLU
          pkgs.xorg.libX11
          pkgs.xorg.libXext
          pkgs.xorg.libXcursor
          pkgs.xorg.libXrandr
          pkgs.xorg.libXinerama
          pkgs.xorg.libXi
          pkgs.xorg.libXxf86vm
        ]}";
      };
    };

    # Create system user and group
    users.users.manyfold = {
      isSystemUser = true;
      group = "manyfold";
      home = "/var/lib/manyfold";
      createHome = true;
    };

    users.groups.manyfold = {};

    # Ensure uploads directory exists with correct permissions
    systemd.tmpfiles.rules = [
      "d '${config.services.manyfold.uploadsPath}' 0750 manyfold manyfold -"
    ];
  };
}
