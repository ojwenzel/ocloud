{ config, pkgs, lib, ... }:

let
  fqdn = "ocloud.zebroid-butterfly.ts.net";
  certDir = "/var/lib/tailscale-certs";
  occ    = "/run/current-system/sw/bin/nextcloud-occ";

  # PHP config file stored in the Nix store (contains no secrets — those are
  # read from /run/secrets/ at PHP runtime via file_get_contents).
  s3ConfigPhp = pkgs.writeText "s3.config.php" ''
    <?php
    $CONFIG = [
      'objectstore' => [
        'class' => 'OC\Files\ObjectStore\S3',
        'arguments' => [
          'bucket'         => 'ocloud-nextcloud',
          'hostname'       => 'nbg1.your-objectstorage.com',
          'port'           => 443,
          'use_ssl'        => true,
          'use_path_style' => true,
          'region'         => 'eu-central-1',
          'key'            => trim(file_get_contents('/run/secrets/s3_access_key')),
          'secret'         => trim(file_get_contents('/run/secrets/s3_secret_key')),
          'autocreate'     => false,
        ],
      ],
    ];
  '';
in
{
  # ── Nextcloud ──────────────────────────────────────────────────────────────

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud31;
    hostName = fqdn;
    https = true;

    database.createLocally = true;
    config = {
      dbtype = "pgsql";
      adminuser = "admin";
      adminpassFile = config.sops.secrets.nextcloud_adminpass.path;
    };

    maxUploadSize = "4G";

    extraApps = {
      # Camera RAW preview support — extracts embedded JPEGs from CR2/NEF/ARW etc.
      camerarawpreviews = pkgs.fetchNextcloudApp {
        url     = "https://github.com/ariselseng/camerarawpreviews/releases/download/v1.0.2/camerarawpreviews_nextcloud.tar.gz";
        hash    = "sha256-PBIBR6JKjPE/co+qmmefAnn5ODoGbRckWjeVwCN0RRM=";
        license = "agpl3Plus";
      };
      # Pre-generates thumbnails in the background so Memories stays fast
      inherit (config.services.nextcloud.package.packages.apps)
        memories
        previewgenerator;
    };
    extraAppsEnable = true;

    settings = lib.mkMerge [
      {
        default_phone_region = "DE";
        trusted_proxies = [ "127.0.0.1" "::1" ];
      }
      # Enable preview providers (toggles in Nextcloud admin → Memories → File Support)
      {
        enabledPreviewProviders = [
          "OC\\Preview\\Image"   # JPEG, PNG, GIF, BMP, WebP
          "OC\\Preview\\HEIC"
          "OC\\Preview\\TIFF"
          "OC\\Preview\\Movie"   # videos via ffmpeg
          "OC\\Preview\\MP3"
          "OC\\Preview\\TXT"
          "OC\\Preview\\MarkDown"
        ];
      }
      # Memories: point to system binaries so it doesn't use its bundled copies
      {
        "memories.exiftool"          = lib.getExe pkgs.exiftool;
        "memories.exiftool_no_local" = true;
        "memories.vod.ffmpeg"        = lib.getExe pkgs.ffmpeg-headless;
        "memories.vod.ffprobe"       = "${pkgs.ffmpeg-headless}/bin/ffprobe";
        "preview_ffmpeg_path"        = lib.getExe pkgs.ffmpeg-headless;
      }
    ];

  };

  # exiftool is a Perl script — the nextcloud-cron service needs Perl in PATH
  # or indexing silently fails.
  systemd.services.nextcloud-cron.path = [ pkgs.perl ];

  # ── Preview Generator size config ─────────────────────────────────────────
  # Runs after every nixos-rebuild switch. occ config:app:set is idempotent so
  # re-running on deploy is harmless. These values live in PostgreSQL.

  systemd.services.nextcloud-previewgenerator-config = {
    description = "Configure Nextcloud previewgenerator thumbnail sizes";
    wantedBy = [ "multi-user.target" ];
    after    = [ "nextcloud-setup.service" ];
    requires = [ "nextcloud-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "nc-previewgenerator-config" ''
        ${occ} -n config:app:set previewgenerator squareSizes --value="256"
        ${occ} -n config:app:set previewgenerator widthSizes  --value="256 1024 2048"
        ${occ} -n config:app:set previewgenerator heightSizes --value="256"
      '';
    };
  };

  # ── S3 primary object store ────────────────────────────────────────────────
  # Copy the static PHP config into Nextcloud's config dir. Nextcloud
  # auto-loads all *.config.php files it finds there.

  system.activationScripts.nextcloud-s3 = lib.stringAfter [ "var" ] ''
    mkdir -p /var/lib/nextcloud/config
    cp ${s3ConfigPhp} /var/lib/nextcloud/config/s3.config.php
    chown nextcloud:nextcloud /var/lib/nextcloud/config/s3.config.php
    chmod 640 /var/lib/nextcloud/config/s3.config.php
  '';

  # ── SSL for the nginx virtualHost Nextcloud creates ────────────────────────

  services.nginx.virtualHosts."${fqdn}" = {
    sslCertificate    = "${certDir}/cert.pem";
    sslCertificateKey = "${certDir}/key.pem";
    forceSSL = true;
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
