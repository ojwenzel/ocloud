{ config, pkgs, ... }:

{
  imports = [
    ../../modules/tailscale.nix
    ../../modules/nginx.nix
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
      networkConfig.DHCP = "ipv4";
      # IPv6 — set your actual /64 prefix here
      address = [ "2a01:4f8:1c19:3814::1/64" ];
      routes = [
        # IPv6 default via link-local gateway (onlink — not in same /64 block)
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
