{ config, pkgs, ... }:

let
  fqdn = "ocloud.zebroid-butterfly.ts.net";
  certDir = "/var/lib/tailscale-certs";
in
{
  # ── Tailscale certificate renewal ─────────────────────────────────────────
  # `tailscale cert` fetches a cert signed by Let's Encrypt via Tailscale's
  # HTTPS certificate infrastructure. Re-runs weekly to renew before 90-day expiry.
  #
  # Prerequisite: DNS → Enable HTTPS Certificates in the Tailscale admin console.

  systemd.services.tailscale-cert = {
    description = "Fetch/renew Tailscale HTTPS certificate for nginx";
    after = [ "tailscaled-autoconnect.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    requires = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
    };
    script = ''
      mkdir -p ${certDir}
      ${pkgs.tailscale}/bin/tailscale cert \
        --cert-file ${certDir}/cert.pem \
        --key-file  ${certDir}/key.pem \
        ${fqdn}
      chown root:${config.services.nginx.group} \
        ${certDir}/cert.pem ${certDir}/key.pem
      chmod 640 ${certDir}/cert.pem ${certDir}/key.pem
      systemctl is-active --quiet nginx.service && \
        systemctl reload --no-block nginx.service || true
    '';
  };

  systemd.timers.tailscale-cert = {
    description = "Weekly Tailscale certificate renewal";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };

  # ── nginx base configuration ───────────────────────────────────────────────
  # Individual services (nextcloud, etc.) add their own virtualHosts.

  systemd.services.nginx = {
    after = [ "tailscale-cert.service" ];
    wants = [ "tailscale-cert.service" ];
  };

  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
  };

  # Expose the cert directory path and fqdn for other modules
  # via a shared let binding — import this file and use the same values.
}
