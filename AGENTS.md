# Repository Conventions & Agent Guidelines

This repository manages NixOS workstation and homelab infrastructure using Nix Flakes, Vaultix secret management, and `mise` task automation.

## 1. Repository Structure & Architecture

- **`flake.nix`**: Flake entrypoint defining NixOS system configurations for target hosts (`homelab1`, `cloud1`, `sandbox1`, `live`).
- **`hosts/`**: Host-specific NixOS configurations (e.g., `hosts/homelab1/configuration.nix`).
- **`modules/`**: Reusable NixOS modules.
  - `modules/services-schema.nix`: Schema definition for services (`myServices`).
  - `modules/services/`: Individual service modules auto-imported per host.
  - System modules (`infra.nix`, `networking.nix`, `storage/`, `kde.nix`, etc.).
- **`home/`**: Home Manager configurations (`user1.nix`, `root.nix`).
- **`secrets/`**: Encrypted secrets (`vaultix` / `age`) and PII specifications (`pii.nix`).
  - `secrets/services.nix` contains the actual data for `services-schema.nix`.
  - note that all the ports should be specified here instead of hardcoding in tmodule
- **`tools/`**: Helper shell scripts.
- **`pkgs/`**: Custom package declarations.

## 2. Secrets & Privacy (PII)

- **`secrets/pii.nix`**: Contains network identities, domain names, user attributes, and host metadata.
- **Vaultix**: Handles secret encryption for host secrets. Never commit unencrypted sensitive credentials or private keys. Secret management is handled manually by the user.
- Reference attributes from `pii` in host/module definitions rather than hardcoding sensitive personal data or IP addresses.

## 3. Workflows & Tooling (`mise`)

The repository uses `mise` (`mise.toml`) for task execution and development workflows:

- **Formatting**: `mise run fmt` (runs `treefmt` / `nixfmt-tree`). Formatting is enforced via pre-commit hooks.
- **Dry-run / Check**:
  - Homelab: `mise run check-homelab`
  - Cloud: `mise run check-cloud`
  - Avoid staging changes to existing files to git before the dry-run. Only stage new files (nix works just fine with dirty files.)
- Prefer to create new mise tasks for repetitive actions, especially those that will extend beyond one session.
- When directly evaluating nix exprs, remember to use `submodules` -- `nix eval ".?submodules=1#nixosConfigurations.foo.bar.baz"`.
- Note: System rebuilds, deployments, and secret edits are performed manually by the user.

## 4. Coding & Verification Guidelines

- **Nix Formatting**: Format code using `mise run fmt` before committing.
- **Service Modules**: Services are declared via `myServices` in `secrets/services.nix`, matching modules in `modules/services/`.
  - if adding new storage paths (like `/var/lib/foobar/`), consider adding a dataset to `modules/datasets/foobar.nix`
- **Machine Ports**: Define host ports in `secrets/services.nix` (`myServices`). Never hardcode machine ports in modules (container-internal ports excepted).
- **Validation**: Ensure Nix syntax and flake outputs remain valid when making changes.
