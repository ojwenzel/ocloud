{ config, pkgs, ... }:

let
  fqdn = "ocloud.zebroid-butterfly.ts.net";
  certDir = "/var/lib/tailscale-certs";
in
{
  # ── Tailscale certificate renewal ─────────────────────────────────────────
  # `tailscale cert` fetches a cert signed by Let's Encrypt via Tailscale's
  # HTTPS certificate infrastructure. It must run after the node has joined
  # the tailnet, and is re-run weekly to renew before the 90-day expiry.
  #
  # Prerequisite: enable HTTPS certificates in the Tailscale admin console
  # under DNS → Enable HTTPS Certificates.

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
      # Reload nginx if it's already running (no-op on first boot)
      systemctl is-active --quiet nginx.service && \
        systemctl reload nginx.service || true
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

  # ── nginx ─────────────────────────────────────────────────────────────────
  # Start nginx only after the cert service has run so the key files exist.

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

    virtualHosts."${fqdn}" = {
      # forceSSL keeps port 80 open only to redirect → 443
      forceSSL = true;
      sslCertificate    = "${certDir}/cert.pem";
      sslCertificateKey = "${certDir}/key.pem";

      locations."/" = {
        # Proxy to a local service, e.g.:
        # proxyPass = "http://127.0.0.1:8080";

        # Or serve static files:
        root = "/var/www/${fqdn}";
      };
    };

    # Additional services — copy the block above and change the location.
    # Each virtualHost can share the same cert since they all use the same fqdn.
    # "sub.${fqdn}" is not possible with Tailscale certs; use path-based routing
    # or expose each service on a different port instead.
  };

  # Ports 80 + 443 are opened in configuration.nix firewall rules.
}
