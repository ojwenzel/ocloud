{ config, pkgs, lib, ... }:

let
  bucket = "ocloud-nextcloud";
  endpoint = "https://nbg1.your-objectstorage.com";
  region = "eu-central-1";
  prefix = "backups/postgres";

  backupScript = pkgs.writeShellApplication {
    name = "nextcloud-pg-backup";
    runtimeInputs = [ config.services.postgresql.package pkgs.rclone pkgs.gzip ];
    text = ''
      set -euo pipefail

      # Credentials from sops — owned by the nextcloud user running this service
      export RCLONE_S3_PROVIDER=Other
      export RCLONE_S3_ACCESS_KEY_ID
      RCLONE_S3_ACCESS_KEY_ID=$(cat /run/secrets/s3_access_key)
      export RCLONE_S3_SECRET_ACCESS_KEY
      RCLONE_S3_SECRET_ACCESS_KEY=$(cat /run/secrets/s3_secret_key)
      export RCLONE_S3_REGION=${region}
      export RCLONE_S3_ENDPOINT=${endpoint}
      # Skip bucket creation/existence check — bucket already exists
      export RCLONE_S3_NO_CHECK_BUCKET=true

      TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
      DEST=":s3:${bucket}/${prefix}/nextcloud-$TIMESTAMP.sql.gz"

      echo "Backing up PostgreSQL → $DEST"
      pg_dump --host=/run/postgresql -U nextcloud nextcloud \
        | gzip -6 \
        | rclone rcat "$DEST"
      echo "Backup complete"

      # Prune backups older than 30 days
      echo "Pruning backups older than 30 days"
      rclone delete ":s3:${bucket}/${prefix}/" --min-age 30d
      echo "Pruning complete"
    '';
  };

in
{
  systemd.services.nextcloud-pg-backup = {
    description = "Nextcloud PostgreSQL backup to S3";
    after = [ "postgresql.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      ExecStart = "${backupScript}/bin/nextcloud-pg-backup";
      # Prevent secrets leaking into the journal
      PrivateTmp = true;
    };
  };

  systemd.timers.nextcloud-pg-backup = {
    description = "Daily Nextcloud PostgreSQL backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00 Europe/Berlin";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };
}
