{ config, pkgs, lib, ... }:

let
  fqdn = "ocloud.zebroid-butterfly.ts.net";
  certDir = "/var/lib/tailscale-certs";

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

    settings = {
      default_phone_region = "DE";
      trusted_proxies = [ "127.0.0.1" "::1" ];
    };

    maxUploadSize = "4G";
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
