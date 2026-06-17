{ config, pkgs, lib, ... }:

let
  bucket   = "ocloud-nextcloud";
  endpoint = "https://nbg1.your-objectstorage.com";
  region   = "eu-central-1";
  prefix   = "backups/postgres";

  # ── Backup ────────────────────────────────────────────────────────────────

  backupScript = pkgs.writeShellApplication {
    name = "nextcloud-pg-backup";
    runtimeInputs = [ config.services.postgresql.package pkgs.rclone pkgs.gzip ];
    text = ''
      set -euo pipefail

      export RCLONE_S3_PROVIDER=Other
      export RCLONE_S3_ACCESS_KEY_ID
      RCLONE_S3_ACCESS_KEY_ID=$(cat /run/secrets/s3_access_key)
      export RCLONE_S3_SECRET_ACCESS_KEY
      RCLONE_S3_SECRET_ACCESS_KEY=$(cat /run/secrets/s3_secret_key)
      export RCLONE_S3_REGION=${region}
      export RCLONE_S3_ENDPOINT=${endpoint}
      export RCLONE_S3_NO_CHECK_BUCKET=true

      TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
      DEST=":s3:${bucket}/${prefix}/nextcloud-$TIMESTAMP.sql.gz"

      echo "Backing up PostgreSQL → $DEST"
      pg_dump --host=/run/postgresql -U nextcloud nextcloud \
        | gzip -6 \
        | rclone rcat "$DEST"
      echo "Backup complete"

      echo "Pruning backups older than 30 days"
      rclone delete ":s3:${bucket}/${prefix}/" --min-age 30d
      echo "Pruning complete"
    '';
  };

  # ── Restore ───────────────────────────────────────────────────────────────

  restoreScript = pkgs.writeShellApplication {
    name = "nextcloud-pg-restore";
    runtimeInputs = [ config.services.postgresql.package pkgs.rclone pkgs.gzip pkgs.gawk ];
    text = ''
      set -euo pipefail

      export RCLONE_S3_PROVIDER=Other
      export RCLONE_S3_ACCESS_KEY_ID
      RCLONE_S3_ACCESS_KEY_ID=$(cat /run/secrets/s3_access_key)
      export RCLONE_S3_SECRET_ACCESS_KEY
      RCLONE_S3_SECRET_ACCESS_KEY=$(cat /run/secrets/s3_secret_key)
      export RCLONE_S3_REGION=${region}
      export RCLONE_S3_ENDPOINT=${endpoint}
      export RCLONE_S3_NO_CHECK_BUCKET=true

      # Check if nextcloud DB is already initialised by looking for any tables
      TABLE_COUNT=$(psql --host=/run/postgresql -U nextcloud nextcloud \
        -tAc "SELECT count(*) FROM information_schema.tables
              WHERE table_schema = 'public';")

      if [ "$TABLE_COUNT" -gt 0 ]; then
        echo "Database already initialised ($TABLE_COUNT tables), skipping restore"
        exit 0
      fi

      echo "Empty database detected — checking S3 for a backup..."

      # Find the most recent backup. rclone lsf --format tp emits lines like:
      #   2026-06-17 03:11:52;nextcloud-2026-06-17_031152.sql.gz
      # Sorted descending (ISO timestamps sort lexicographically), take first,
      # split on ; and take the filename after it.
      LATEST=$(rclone lsf ":s3:${bucket}/${prefix}/" \
        --format tp --files-only \
        | sort -r | head -1 | awk -F';' '{print $NF}')

      if [ -z "$LATEST" ]; then
        echo "No backup found on S3 — starting fresh"
        exit 0
      fi

      echo "Restoring from s3://${bucket}/${prefix}/$LATEST"
      rclone cat ":s3:${bucket}/${prefix}/$LATEST" \
        | gunzip \
        | psql --host=/run/postgresql -U nextcloud nextcloud
      echo "Restore complete"
    '';
  };

in
{
  # ── Backup service + timer ─────────────────────────────────────────────────

  systemd.services.nextcloud-pg-backup = {
    description = "Nextcloud PostgreSQL backup to S3";
    after = [ "postgresql.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      ExecStart = "${backupScript}/bin/nextcloud-pg-backup";
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

  # ── Restore service ────────────────────────────────────────────────────────
  # Runs on every boot before nextcloud-setup. On an existing system it exits
  # immediately (tables already present). On a fresh install it checks S3 and
  # restores the latest backup if one exists.

  systemd.services.nextcloud-pg-restore = {
    description = "Restore Nextcloud PostgreSQL from S3 (if fresh install)";
    after  = [ "postgresql.service" "network-online.target" ];
    wants  = [ "network-online.target" ];
    before = [ "nextcloud-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      ExecStart = "${restoreScript}/bin/nextcloud-pg-restore";
      RemainAfterExit = true;
      PrivateTmp = true;
    };
  };

  # Ensure nextcloud-setup waits for the restore attempt — uses `wants` so a
  # restore failure (e.g. no network) still lets a fresh install proceed.
  systemd.services.nextcloud-setup = {
    after = [ "nextcloud-pg-restore.service" ];
    wants = [ "nextcloud-pg-restore.service" ];
  };
}
