{ config, pkgs, ... }:

{
  imports = [
    ../../modules/tailscale.nix
    ../../modules/nginx.nix
    ../../modules/redis.nix
    ../../modules/nextcloud.nix
    ../../modules/backup.nix
  ];

  # ── System ────────────────────────────────────────────────────────────────

  networking.hostName = "ocloud";
  time.timeZone = "Europe/Berlin";
  system.stateVersion = "25.05";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    # Allow nixos-rebuild from remote without sudo prompts
    trusted-users = [ "root" "@wheel" ];
  };

  # ── Bootloader ────────────────────────────────────────────────────────────
  # Hetzner Cloud supports UEFI. efiInstallAsRemovable is required because
  # Hetzner does not persist EFI boot entries across reboots/rescue boots.

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };
  boot.loader.efi.canTouchEfiVariables = false;

  # Kernel modules for virtio storage and networking on Hetzner KVM
  boot.initrd.availableKernelModules = [
    "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];

  # ── Networking ────────────────────────────────────────────────────────────
  # IPv4: DHCP (Hetzner provides 100.64.x.x/32 via DHCP, public IP is routed)
  # IPv6: static /64 with link-local gateway fe80::1
  # Interface name on Hetzner Cloud KVM: eth0

  networking.useDHCP = false;
  # Force eth0 instead of predictable names (enp1s0 etc.) on Hetzner KVM
  networking.usePredictableInterfaceNames = false;

  systemd.network = {
    enable = true;
    networks."10-eth0" = {
      matchConfig.Name = "eth0";
      # This server has no public IPv4 (disabled at Hetzner to avoid the per-IP
      # fee). IPv4 DHCP provides only a 100.64/10 CGNAT management address with
      # no internet connectivity.  All outbound traffic goes over IPv6.
      #
      # IPv4-only hosts (notably GitHub) are reachable via Cloudflare's DNS64 +
      # NAT64 service: the DNS64 resolvers synthesise AAAA records in the
      # Well-Known 64:ff9b::/96 prefix, and Cloudflare's NAT64 gateway
      # translates the resulting IPv6 packets to IPv4.
      networkConfig = {
        DHCP = "ipv4";
        # Hetzner's IPv6 DNS resolvers — reliable, low-latency from NBG1.
        # (IPv4 DHCP lease provides no DNS; Fallback DNS from systemd-resolved
        # defaults are IPv4-only and unreachable on this IPv6-only server.)
        DNS  = [ "2a01:4ff:ff00::add:1" "2a01:4ff:ff00::add:2" ];
      };
      address = [ "2a01:4f8:1c19:3814::1/64" ];
      routes = [
        { Gateway = "fe80::1"; GatewayOnLink = true; }
      ];
      ipv6AcceptRAConfig.Token = "static:::1";
    };
  };

  # ── SSH ───────────────────────────────────────────────────────────────────
  # Initially open on all interfaces. Once Tailscale is up and verified
  # (server appears as ocloud.zebroid-butterfly.ts.net), lock SSH to Tailscale:
  #   services.openssh.listenAddresses = [{ addr = "100.x.x.x"; port = 22; }];
  # Get the Tailscale IP with: tailscale ip -4  (run on the server)

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAOjHFE3jCNPDmca4HXAuOsfggd6HdY4LWTDpj9BkXIg ojwenzel@t460"
  ];

  # ── Firewall ──────────────────────────────────────────────────────────────

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    # Allow all traffic from Tailscale peers unconditionally
    trustedInterfaces = [ "tailscale0" ];
  };

  # ── Secrets (sops-nix) ────────────────────────────────────────────────────
  # Secrets are decrypted at boot using the host's SSH ed25519 key.
  # Generate your age key from the host key after first deploy:
  #   ssh-keyscan ocloud | ssh-to-age
  # Then add to .sops.yaml and re-encrypt secrets.

  sops = {
    defaultSopsFile = ../../secrets/ocloud/secrets.yaml;
    # Derive age key from the host's SSH ed25519 host key
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.tailscale_authkey = {};
    secrets.nextcloud_adminpass = {};
    secrets.s3_access_key = { owner = "nextcloud"; };
    secrets.s3_secret_key = { owner = "nextcloud"; };
  };

  # ── Packages ──────────────────────────────────────────────────────────────

  environment.systemPackages = with pkgs; [
    git
    curl
    htop
    vim
  ];
}
