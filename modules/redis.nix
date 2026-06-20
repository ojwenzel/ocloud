{ config, pkgs, ... }:

{
  # ── Redis (Valkey) ─────────────────────────────────────────────────────────
  # Provides two caching roles for Nextcloud:
  #   memcache.distributed  — shared object cache across all PHP-FPM workers
  #   memcache.locking      — file lock coordination (replaces per-request
  #                           PostgreSQL advisory locks, large speedup under
  #                           concurrent iOS / desktop client requests)
  #
  # Reproducibility: no backup needed.  Redis holds only ephemeral caches and
  # transient lock state.  On restart everything is cold and repopulated
  # automatically from PostgreSQL and APCu — nothing here is worth preserving.

  # Use Valkey (Linux Foundation Redis fork) instead of Redis for all servers.
  services.redis.package = pkgs.valkey;

  services.redis.servers.nextcloud = {
    enable = true;

    # Unix socket: lower latency than TCP for same-host IPC; never exposed on
    # any network interface.
    unixSocket     = "/run/redis-nextcloud/redis.sock";
    unixSocketPerm = 770;    # nextcloud user accesses via the redis-nextcloud group

    # Disable all persistence — we want an ephemeral cache, not RDB snapshots
    # written to disk on every save interval.
    save = [];

    settings = {
      maxmemory        = "256mb";
      maxmemory-policy = "allkeys-lru";  # evict least-recently-used on pressure
    };
  };

  # PHP-FPM runs as user `nextcloud`.  Add it to the auto-created group so it
  # can reach the Unix socket (770 = owner:group only).
  users.users.nextcloud.extraGroups = [ "redis-nextcloud" ];
}
