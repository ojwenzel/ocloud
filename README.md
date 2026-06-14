# o-cloud

NixOS configuration for a Hetzner Cloud CX22 VPS (2 vCPU, 4 GB RAM, 38 GB disk). The server runs nginx with TLS certificates issued through Tailscale's HTTPS certificate infrastructure and joins a Tailscale tailnet for private access. The entire system — disk layout, services, secrets — is declared in this flake and deployed without ever touching a rescue system or ISO image.

## Repository layout

```
flake.nix                     # inputs: nixpkgs 25.05, disko, sops-nix
hosts/ocloud/
  configuration.nix           # main NixOS config (networking, SSH, firewall, sops)
  disk-config.nix             # disko GPT layout for /dev/sda
modules/
  tailscale.nix               # tailscale service + firewall
  nginx.nix                   # nginx reverse proxy + Tailscale TLS cert renewal
secrets/ocloud/
  secrets.yaml                # sops-encrypted secrets (tailscale OAuth client secret)
.sops.yaml                    # age key recipients for encryption
```

## Prerequisites

- Nix with flakes enabled on your local machine
- A [Tailscale](https://tailscale.com) account with an existing tailnet
- A Hetzner Cloud server (CX22 or similar) running any Linux OS
- A domain you control, pointed at the server's IP (for the nginx placeholder — optional if serving only via Tailscale hostname)

## Initial setup

### 1. Install tools

```bash
nix-shell -p age sops ssh-to-age
```

### 2. Create a local age key

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
# Copy the "Public key: age1..." line into .sops.yaml, replacing the placeholder
```

### 3. Set up Tailscale

**a. Define a tag** in your tailnet ACL policy at <https://login.tailscale.com/admin/acls>:
```json
{
  "tagOwners": {
    "tag:ocloud": ["autogroup:admin"]
  }
}
```

**b. Enable HTTPS certificates** at <https://login.tailscale.com/admin/dns> → HTTPS Certificates → Enable.

**c. Create an OAuth client** at <https://login.tailscale.com/admin/settings/oauth>:
- Scope: `auth_keys` → Write
- Tag: `tag:ocloud`
- Copy the `tskey-client-...` secret — it never expires

### 4. Configure nginx

Edit `modules/nginx.nix` and set your domain and contact email (or leave the Tailscale hostname as-is for internal-only access).

### 5. Configure the SSH authorized key

The `hosts/ocloud/configuration.nix` file contains an `authorizedKeys.keys` list. Add your SSH public key there.

### 6. Encrypt secrets

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops secrets/ocloud/secrets.yaml
```

Your editor opens. Set the Tailscale OAuth client secret and save — sops encrypts in place:
```yaml
tailscale_authkey: tskey-client-XXXXXXXXXXXXXXXXXXXXXX
```

### 7. Boot into Hetzner rescue mode

nixos-anywhere uses kexec to boot into the NixOS installer, but Ubuntu kernels on Hetzner have lockdown enabled which blocks kexec. The workaround is to boot into the Hetzner rescue system first (which has no lockdown):

1. Go to the Hetzner Cloud console → your server → **Enable Rescue System** → power cycle
2. Clear any stale SSH host key locally: `ssh-keygen -R <server-ip>`

### 8. Deploy

This command wipes `/dev/sda` and installs NixOS. **The disk is fully erased.**

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake '.#ocloud' \
  --target-host root@<server-ip> \
  --build-on-remote
```

The server reboots into NixOS and joins the tailnet as `ocloud.zebroid-butterfly.ts.net` within a minute.

### 9. Add the host key to sops (post-deploy)

On first boot the server's SSH host key is generated. Add it to sops so secrets can be decrypted on future reboots without your local key:

```bash
# Get the host's age public key
ssh-keyscan <server-ip> | ssh-to-age

# Add the age1... output to .sops.yaml alongside the existing key, then update:
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  sops updatekeys --yes secrets/ocloud/secrets.yaml
```

Then push the updated secrets:

```bash
nixos-rebuild switch \
  --flake '.#ocloud' \
  --target-host root@ocloud \
  --use-remote-sudo
```

## Upgrading

Push config changes or NixOS upgrades to the running server:

```bash
nixos-rebuild switch \
  --flake '.#ocloud' \
  --target-host root@ocloud \
  --use-remote-sudo
```

To upgrade nixpkgs or other inputs:

```bash
nix flake update          # update all inputs
nix flake update nixpkgs  # update only nixpkgs
```

Then redeploy with the command above.
