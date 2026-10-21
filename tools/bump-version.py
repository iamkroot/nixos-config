#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "tomlkit>=0.13.0",
#     "aioregistry",
# ]
# ///

import argparse
import asyncio
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path
from aioregistry import AsyncRegistryClient, parse_image_name
import tomlkit


def resolve_nix_prefetch_hash(url: str) -> str:
    """Calculates the SRI sha256 hash of an unpacked tarball using nix-prefetch-url."""
    print(f"Prefetching {url} ...", file=sys.stderr)
    proc = subprocess.run(["nix-prefetch-url", "--unpack", url], capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"nix-prefetch-url failed for {url}: {proc.stderr}")
    raw_hash = proc.stdout.strip()
    convert_proc = subprocess.run(
        ["nix", "hash", "convert", "--hash-algo", "sha256", "--to", "sri", raw_hash],
        capture_output=True,
        text=True,
    )
    if convert_proc.returncode != 0:
        raise RuntimeError(f"nix hash convert failed: {convert_proc.stderr}")
    return convert_proc.stdout.strip()


def resolve_npm_hash(github_repo: str, tag: str) -> str:
    """Calculates npmHash by downloading package-lock.json and running prefetch-npm-deps."""
    url = f"https://raw.githubusercontent.com/{github_repo}/{tag}/package-lock.json"
    print(f"Fetching package-lock.json from {url} ...", file=sys.stderr)
    with tempfile.NamedTemporaryFile("wb", delete=False) as tf:
        temp_path = tf.name

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "nixos-bumper"})
        with urllib.request.urlopen(req) as resp:
            data = resp.read()
        with open(temp_path, "wb") as f:
            f.write(data)

        proc = subprocess.run(
            ["nix-shell", "-p", "prefetch-npm-deps", "--run", f"prefetch-npm-deps '{temp_path}'"],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            raise RuntimeError(f"prefetch-npm-deps failed: {proc.stderr}")
        return proc.stdout.strip().splitlines()[-1].strip()
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)


def resolve_git_tag_commit(github_repo: str, tag: str) -> str | None:
    """Resolves commit SHA for a git tag using git ls-remote, dereferencing annotated tags."""
    proc = subprocess.run(
        ["git", "ls-remote", "-t", f"https://github.com/{github_repo}.git", f"refs/tags/{tag}*"],
        capture_output=True,
        text=True,
    )
    if proc.returncode == 0 and proc.stdout.strip():
        lines = proc.stdout.strip().splitlines()
        # Prefer peeled tag commit ^{} for annotated tags
        peeled = [l.split()[0] for l in lines if l.endswith("^{}")]
        if peeled:
            return peeled[0]
        for l in lines:
            parts = l.split()
            if len(parts) >= 2 and parts[1] == f"refs/tags/{tag}":
                return parts[0]
        return lines[0].split()[0]
    return None


def resolve_cargo_hash(github_repo: str, rev: str, hash_val: str) -> str:
    """Calculates cargoHash using pkgs.rustPlatform.fetchCargoVendor in nix-build."""
    owner, repo = github_repo.split("/", 1)
    nix_expr = f"""
    let
      pkgs = import <nixpkgs> {{}};
      src = pkgs.fetchFromGitHub {{
        owner = "{owner}";
        repo = "{repo}";
        rev = "{rev}";
        hash = "{hash_val}";
      }};
    in pkgs.rustPlatform.fetchCargoVendor {{
      inherit src;
      name = "{repo}-vendor";
      hash = pkgs.lib.fakeHash;
    }}
    """
    print(f"Resolving cargoHash for {github_repo} ({rev}) via nix-build ...", file=sys.stderr)
    proc = subprocess.run(["nix-build", "--no-out-link", "-E", nix_expr], capture_output=True, text=True)
    for line in proc.stderr.splitlines():
        if "got:" in line:
            return line.split("got:", 1)[1].strip()
    raise RuntimeError(f"Could not extract cargoHash from nix-build:\n{proc.stderr}")


async def _lookup_digest(repository: str, candidate: str) -> str | None:
    async with AsyncRegistryClient() as client:
        ref = parse_image_name(f"{repository}:{candidate}")
        res = await client.ref_lookup(ref)
        if res and res.digest:
            return res.digest
        return None


def resolve_image_digest(repository: str, target_tag: str, current_tag: str | None = None) -> tuple[str, str]:
    """Resolves the OCI manifest digest for repository:target_tag using aioregistry.
    Normalizes tag prefix ('v' vs raw) and preserves flavor suffixes (e.g. -gows, -dev).
    Returns: (resolved_tag, digest)
    """
    raw_version = target_tag.lstrip("v")
    v_version = f"v{raw_version}"

    candidates = []

    # Preserve flavor tag / suffix if current_tag has one (e.g. "gows", "dev", "1.2.3-alpine")
    if current_tag:
        flavor = None
        if "-" in current_tag:
            flavor = current_tag.split("-", 1)[1]
        elif not any(c.isdigit() for c in current_tag):
            flavor = current_tag

        if flavor:
            candidates.extend([
                f"{raw_version}-{flavor}",
                f"{v_version}-{flavor}",
            ])
            if not any(c.isdigit() for c in target_tag):
                candidates.append(flavor)

        if current_tag.startswith("v"):
            candidates.extend([v_version, raw_version])
        else:
            candidates.extend([raw_version, v_version])
    else:
        candidates.extend([target_tag, raw_version, v_version])

    # Remove duplicates while preserving order
    unique_candidates = []
    for c in candidates:
        if c not in unique_candidates:
            unique_candidates.append(c)

    last_error = ""
    for candidate in unique_candidates:
        image_ref = f"{repository}:{candidate}"
        print(f"Resolving digest for {image_ref} ...", file=sys.stderr)

        for attempt in range(1, 4):
            try:
                digest = asyncio.run(_lookup_digest(repository, candidate))
                if digest:
                    return candidate, digest
                else:
                    last_error = f"Tag {candidate} not found in {repository}"
                    break
            except Exception as e:
                last_error = str(e)
                time.sleep(2 * attempt)

    raise RuntimeError(
        f"Failed to resolve manifest digest for {repository} with candidates {unique_candidates}: {last_error.strip()}"
    )


def bump_service(doc, service_name: str, new_version: str) -> list[str]:
    """Bumps a service, suite, or source package in the tomlkit document.
    Returns a list of change descriptions.
    """
    changes = []
    if service_name not in doc:
        raise KeyError(f"Service '{service_name}' not found in versions document.")

    item = doc[service_name]
    raw_ver = new_version.lstrip("v")
    curr_suite_tag = item.get("tag") or item.get("version") or ""
    resolved_suite = f"v{raw_ver}" if curr_suite_tag.startswith("v") else raw_ver

    # 1. Update top-level version/tag if declared
    if "repository" in item:
        repo = item["repository"]
        resolved_tag, digest = resolve_image_digest(repo, new_version, curr_suite_tag)

        if "tag" in item and item["tag"] != resolved_tag:
            changes.append(f"{service_name}.tag: {item['tag']} -> {resolved_tag}")
            item["tag"] = resolved_tag
        elif "version" in item and item["version"] != resolved_tag:
            changes.append(f"{service_name}.version: {item['version']} -> {resolved_tag}")
            item["version"] = resolved_tag

        if item.get("digest") != digest:
            changes.append(f"{service_name}.digest: {item.get('digest')} -> {digest}")
            item["digest"] = digest
    elif "tag" in item or "version" in item:
        target_field = "tag" if "tag" in item else "version"
        if item[target_field] != resolved_suite:
            changes.append(f"{service_name}.{target_field}: {item[target_field]} -> {resolved_suite}")
            item[target_field] = resolved_suite

    # 2. Inspect subcomponents (e.g. immich.*, windmill.*, revaulter.cli)
    sub_items = {k: v for k, v in item.items() if isinstance(v, dict)}
    for sub_name, sub_item in sub_items.items():
        if "repository" in sub_item:
            repo = sub_item["repository"]
            # Skip auxiliary images that should not be bumped with suite
            if sub_name in ("postgres", "memcached", "valkey", "redis"):
                continue
            # Skip sub-images with distinct pinned tags (e.g. postgres 14/18, valkey 9)
            if "tag" in sub_item and curr_suite_tag and sub_item["tag"] != curr_suite_tag:
                continue
            if "version" in sub_item and curr_suite_tag and sub_item["version"] != curr_suite_tag:
                continue
            # If suite has no version/tag, skip subcomponents unless they match requested version or are primary
            if not curr_suite_tag and sub_name not in ("app", "server", service_name):
                continue

            sub_curr_tag = sub_item.get("tag") or sub_item.get("version") or curr_suite_tag
            resolved_sub_tag, digest = resolve_image_digest(repo, new_version, sub_curr_tag)

            if "tag" in sub_item and sub_item["tag"] != resolved_sub_tag:
                changes.append(f"{service_name}.{sub_name}.tag: {sub_item['tag']} -> {resolved_sub_tag}")
                sub_item["tag"] = resolved_sub_tag
            elif "version" in sub_item and sub_item["version"] != resolved_sub_tag:
                changes.append(f"{service_name}.{sub_name}.version: {sub_item['version']} -> {resolved_sub_tag}")
                sub_item["version"] = resolved_sub_tag

            if sub_item.get("digest") != digest:
                changes.append(f"{service_name}.{sub_name}.digest: {sub_item.get('digest')} -> {digest}")
                sub_item["digest"] = digest

        elif "hash" in sub_item and "upstream" in item and item["upstream"].startswith("github:"):
            github_repo = item["upstream"].removeprefix("github:")
            sub_raw = raw_ver
            if "version" in sub_item and sub_item["version"] != sub_raw:
                changes.append(f"{service_name}.{sub_name}.version: {sub_item['version']} -> {sub_raw}")
                sub_item["version"] = sub_raw

            # Query GitHub Releases API to locate actual binary release asset
            download_url = None
            release_tags = [f"v{sub_raw}", sub_raw]
            for rtag in release_tags:
                try:
                    rel_api = f"https://api.github.com/repos/{github_repo}/releases/tags/{rtag}"
                    req = urllib.request.Request(rel_api, headers={"User-Agent": "nixos-bumper"})
                    with urllib.request.urlopen(req) as resp:
                        rel_data = json.loads(resp.read().decode())
                        for asset in rel_data.get("assets", []):
                            aname = asset.get("name", "").lower()
                            if "linux" in aname and "amd64" in aname and (aname.endswith(".tar.gz") or aname.endswith(".zip")):
                                download_url = asset.get("browser_download_url")
                                break
                    if download_url:
                        break
                except Exception:
                    pass

            if not download_url:
                repo_tail = github_repo.split("/")[-1]
                download_url = f"https://github.com/{github_repo}/releases/download/v{sub_raw}/{repo_tail}-{sub_raw}-linux-amd64.tar.gz"

            new_sub_hash = resolve_nix_prefetch_hash(download_url)
            if sub_item.get("hash") != new_sub_hash:
                changes.append(f"{service_name}.{sub_name}.hash: {sub_item.get('hash')} -> {new_sub_hash}")
                sub_item["hash"] = new_sub_hash

    # 3. Source package resolution (if top-level declares upstream/hash/cargoHash/npmHash/rev)
    if "repository" not in item and "upstream" in item and item["upstream"].startswith("github:"):
        github_repo = item["upstream"].removeprefix("github:")
        tag_candidate = resolved_suite

        if "hash" in item:
            url_candidates = [
                f"https://github.com/{github_repo}/archive/refs/tags/{tag_candidate}.tar.gz",
                f"https://github.com/{github_repo}/archive/refs/tags/v{raw_ver}.tar.gz",
                f"https://github.com/{github_repo}/archive/{tag_candidate}.tar.gz",
                f"https://github.com/{github_repo}/archive/{raw_ver}.tar.gz",
            ]
            new_hash = None
            last_err = None
            for tar_url in url_candidates:
                try:
                    new_hash = resolve_nix_prefetch_hash(tar_url)
                    break
                except Exception as e:
                    last_err = e
            if not new_hash:
                raise RuntimeError(f"Failed to prefetch tarball for {github_repo}: {last_err}")

            if item.get("hash") != new_hash:
                changes.append(f"{service_name}.hash: {item.get('hash')} -> {new_hash}")
                item["hash"] = new_hash

        if "rev" in item:
            commit = resolve_git_tag_commit(github_repo, tag_candidate)
            if not commit and len(raw_ver) == 40 and all(c in "0123456789abcdefABCDEF" for c in raw_ver):
                commit = raw_ver
            if commit and item.get("rev") != commit:
                changes.append(f"{service_name}.rev: {item.get('rev')} -> {commit}")
                item["rev"] = commit

        if "npmHash" in item:
            new_npm_hash = resolve_npm_hash(github_repo, tag_candidate)
            if item.get("npmHash") != new_npm_hash:
                changes.append(f"{service_name}.npmHash: {item.get('npmHash')} -> {new_npm_hash}")
                item["npmHash"] = new_npm_hash

        if "cargoHash" in item:
            rev_val = item.get("rev") or tag_candidate
            hash_val = item.get("hash", "")
            new_cargo_hash = resolve_cargo_hash(github_repo, rev_val, hash_val)
            if item.get("cargoHash") != new_cargo_hash:
                changes.append(f"{service_name}.cargoHash: {item.get('cargoHash')} -> {new_cargo_hash}")
                item["cargoHash"] = new_cargo_hash

    return changes


def main():
    parser = argparse.ArgumentParser(description="Bump versions and resolve OCI digests in versions.toml")
    parser.add_argument("service", help="Service name (e.g. wallos, immich)")
    parser.add_argument("version", help="Target version or tag (e.g. 5.8.4, v3.3.4)")
    parser.add_argument(
        "--file",
        "-f",
        default="versions.toml",
        help="Path to versions.toml (default: versions.toml)",
    )
    parser.add_argument(
        "--dry-run",
        "-n",
        action="store_true",
        help="Print changes without modifying file",
    )

    args = parser.parse_args()

    file_path = Path(args.file)
    if not file_path.exists():
        script_root = Path(__file__).resolve().parent.parent
        alt_path = script_root / args.file
        if alt_path.exists():
            file_path = alt_path
        else:
            sys.exit(f"Error: Could not find {args.file}")

    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    doc = tomlkit.parse(content)

    changes = bump_service(doc, args.service, args.version)

    if not changes:
        print(f"No changes needed: {args.service} is already at version {args.version} with matching digest.")
        return

    print(f"Proposed changes for {args.service}:")
    for ch in changes:
        print(f"  - {ch}")

    if not args.dry_run:
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(tomlkit.dumps(doc))
        print(f"Successfully updated {file_path}")
    else:
        print("[dry-run] File was not modified.")


if __name__ == "__main__":
    main()
