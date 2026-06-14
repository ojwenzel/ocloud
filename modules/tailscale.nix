{ config, pkgs, lib, ... }:

{
  services.tailscale = {
    enable = true;
    # When set, NixOS runs `tailscale up --authkey <file>` on first boot
    # automatically via the builtin tailscaled-autoconnect.service.
    # Use a reusable pre-auth key from https://login.tailscale.com/admin/settings/keys
    authKeyFile = config.sops.secrets.tailscale_authkey.path;
    # Set to "server" if this node should act as a subnet router or exit node
    useRoutingFeatures = "client";
    # Extra flags passed to `tailscale up`
    # Server will appear as ocloud.zebroid-butterfly.ts.net after joining.
    # --advertise-tags is required when authenticating with an OAuth client secret.
    extraUpFlags = [
      "--hostname=ocloud"
      "--advertise-tags=tag:ocloud"
    ];
  };

  # Trust all traffic arriving on the Tailscale interface — this is safe
  # because Tailscale already authenticates and encrypts all peers.
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];

  # Force nftables backend to avoid conflicts with iptables on newer kernels
  systemd.services.tailscaled.serviceConfig.Environment = [
    "TS_DEBUG_FIREWALL_MODE=nftables"
  ];

  # sops secrets are installed by the activation script before any services
  # start, so no explicit ordering is needed here. The authkey file at
  # /run/secrets/tailscale_authkey is guaranteed to exist by the time
  # tailscaled-autoconnect.service runs on a normal boot.
}
