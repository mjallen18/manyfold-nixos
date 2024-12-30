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
