# Phase 5: CI/CD Pipeline

**Goal**: Every push to `dev` automatically builds all 6 ISOs (3 editions × 2 arches). Tagged releases publish ISOs with checksums and signatures.

**Prerequisite**: Phase 4: Installer complete for your target track — [Ubuntu](ubuntu/phases/PHASE4_INSTALLER.md) | [Debian](debian/phases/PHASE4_INSTALLER.md)

---

## Overview

```
Push to dev     → build all editions → upload as draft artifacts
Push to main    → build + smoke tests
Tag v*          → full release build → publish to GitHub Releases
```

All builds run on GitHub-hosted runners using the matrix strategy. ARM64 uses GitHub's native arm64 runners (available on paid plans) or self-hosted runners.

---

## Step 5.1 — Repository Secrets and Settings

Before writing workflows, configure these in **Settings → Secrets and variables → Actions**:

| Secret | Value | Purpose |
|---|---|---|
| `GPG_PRIVATE_KEY` | Armored export of distro signing key | Sign SHA256SUMS |
| `GPG_PASSPHRASE` | Passphrase for the signing key | Unlock key during signing |

### Generate the distro signing key
```bash
# On your local machine (not the build host)
gpg --full-generate-key
# Type: RSA 4096
# Name: MyDistro Release
# Email: releases@mydistro.example.com
# Passphrase: (store securely)

# Export for GitHub secret
gpg --armor --export-secret-keys releases@mydistro.example.com > mydistro-private.key
# Paste contents of mydistro-private.key into the GPG_PRIVATE_KEY secret

# Export public key — commit this to the repo
gpg --armor --export releases@mydistro.example.com > distro-signing-key.asc
git add distro-signing-key.asc
```

---

## Step 5.2 — Makefile Updates

Add targets needed by CI:

**`Makefile`** (expanded from Phase 1):
```makefile
SHELL        := /bin/bash
EDITIONS     := server desktop developer
ARCH         ?= amd64
DISTRO_VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo "dev")

.PHONY: all $(EDITIONS) checksums sign clean clean-edition

all: $(EDITIONS)

$(EDITIONS):
	@echo "==> Building $@ edition ($(ARCH))..."
	@mkdir -p build/$@ output
	@cp -r common/. build/$@/
	@cp -r editions/$@/. build/$@/
	@cd build/$@ && lb config \
	    $(shell cat editions/$@/lb-config | tr '\n' ' ') \
	    --architectures $(ARCH) \
	    --mirror-bootstrap http://archive.ubuntu.com/ubuntu/ \
	    --mirror-binary http://archive.ubuntu.com/ubuntu/
	@cd build/$@ && sudo lb build 2>&1 | tee ../../output/build-$@-$(ARCH).log
	@mv build/$@/live-image-$(ARCH).hybrid.iso \
	    output/mydistro-$(DISTRO_VERSION)-$@-$(ARCH).iso
	@echo "==> Done: output/mydistro-$(DISTRO_VERSION)-$@-$(ARCH).iso"

checksums:
	@cd output && sha256sum *.iso > SHA256SUMS
	@echo "==> SHA256SUMS written"
	@cat output/SHA256SUMS

sign:
	@[ -n "$(GPG_KEY_ID)" ] || (echo "Usage: make sign GPG_KEY_ID=<keyid>" && exit 1)
	@cd output && gpg --armor --detach-sign --local-user "$(GPG_KEY_ID)" SHA256SUMS
	@echo "==> SHA256SUMS.asc written"

clean-edition:
	@[ -n "$(EDITION)" ] || (echo "Usage: make clean-edition EDITION=server" && exit 1)
	sudo rm -rf build/$(EDITION)

clean:
	sudo rm -rf build/ output/
```

---

## Step 5.3 — GitHub Actions Workflows

Create `.github/workflows/` directory:
```bash
mkdir -p .github/workflows
```

### Workflow 1: Build on push to `dev`

**`.github/workflows/build-dev.yml`**
```yaml
name: Build (dev)

on:
  push:
    branches:
      - dev

jobs:
  build:
    name: ${{ matrix.edition }} / ${{ matrix.arch }}
    strategy:
      fail-fast: false
      matrix:
        edition: [server, desktop, developer]
        arch: [amd64, arm64]
    runs-on: ${{ matrix.arch == 'arm64' && 'ubuntu-24.04-arm' || 'ubuntu-24.04' }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install build dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y \
            live-build \
            qemu-user-static \
            binfmt-support \
            debootstrap \
            squashfs-tools \
            xorriso \
            isolinux \
            syslinux-efi \
            grub-efi-amd64-bin \
            grub-efi-arm64-bin \
            grub-pc-bin

      - name: Enable binfmt
        run: sudo systemctl restart binfmt-support

      - name: Build ISO
        run: make ${{ matrix.edition }} ARCH=${{ matrix.arch }}

      - name: Upload ISO
        uses: actions/upload-artifact@v4
        with:
          name: mydistro-dev-${{ matrix.edition }}-${{ matrix.arch }}
          path: output/*.iso
          retention-days: 7

      - name: Upload build log
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: log-${{ matrix.edition }}-${{ matrix.arch }}
          path: output/build-*.log
          retention-days: 3
```

### Workflow 2: Build + smoke test on push to `main`

**`.github/workflows/build-main.yml`**
```yaml
name: Build (main)

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

jobs:
  build:
    name: ${{ matrix.edition }} / ${{ matrix.arch }}
    strategy:
      fail-fast: false
      matrix:
        edition: [server, desktop, developer]
        arch: [amd64, arm64]
    runs-on: ${{ matrix.arch == 'arm64' && 'ubuntu-24.04-arm' || 'ubuntu-24.04' }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install build dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y \
            live-build \
            qemu-user-static \
            binfmt-support \
            debootstrap \
            squashfs-tools \
            xorriso \
            isolinux \
            syslinux-efi \
            grub-efi-amd64-bin \
            grub-efi-arm64-bin \
            grub-pc-bin \
            qemu-system-x86-64 \
            qemu-system-arm \
            ovmf

      - name: Enable binfmt
        run: sudo systemctl restart binfmt-support

      - name: Build ISO
        run: make ${{ matrix.edition }} ARCH=${{ matrix.arch }}

      - name: Smoke test — verify ISO metadata
        run: |
          ISO="output/mydistro-*-${{ matrix.edition }}-${{ matrix.arch }}.iso"
          # Check ISO is non-zero in size
          ls -lh $ISO
          SIZE=$(stat -c%s output/mydistro-*-${{ matrix.edition }}-${{ matrix.arch }}.iso)
          [ "$SIZE" -gt 104857600 ] || (echo "ISO too small" && exit 1)

      - name: Smoke test — mount and check os-release
        run: |
          ISO=$(ls output/mydistro-*-${{ matrix.edition }}-${{ matrix.arch }}.iso)
          mkdir -p /tmp/iso-mount
          sudo mount -o loop "$ISO" /tmp/iso-mount 2>/dev/null || \
            sudo mount -o loop,ro "$ISO" /tmp/iso-mount
          # Check os-release in squashfs
          SQUASHFS=$(find /tmp/iso-mount -name "*.squashfs" | head -1)
          sudo unsquashfs -d /tmp/squash-extract "$SQUASHFS" etc/os-release
          grep -q "MyDistro" /tmp/squash-extract/etc/os-release || \
            (echo "os-release does not contain MyDistro" && exit 1)
          sudo umount /tmp/iso-mount
          sudo rm -rf /tmp/squash-extract /tmp/iso-mount

      - name: Upload ISO
        uses: actions/upload-artifact@v4
        with:
          name: mydistro-${{ matrix.edition }}-${{ matrix.arch }}
          path: output/*.iso
          retention-days: 14
```

### Workflow 3: Release on tag

**`.github/workflows/release.yml`**
```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    name: ${{ matrix.edition }} / ${{ matrix.arch }}
    strategy:
      fail-fast: false
      matrix:
        edition: [server, desktop, developer]
        arch: [amd64, arm64]
    runs-on: ${{ matrix.arch == 'arm64' && 'ubuntu-24.04-arm' || 'ubuntu-24.04' }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0   # needed for git describe

      - name: Install build dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y \
            live-build \
            qemu-user-static \
            binfmt-support \
            debootstrap \
            squashfs-tools \
            xorriso \
            isolinux \
            syslinux-efi \
            grub-efi-amd64-bin \
            grub-efi-arm64-bin \
            grub-pc-bin

      - name: Enable binfmt
        run: sudo systemctl restart binfmt-support

      - name: Build ISO
        run: make ${{ matrix.edition }} ARCH=${{ matrix.arch }}

      - name: Upload ISO artifact
        uses: actions/upload-artifact@v4
        with:
          name: release-${{ matrix.edition }}-${{ matrix.arch }}
          path: output/*.iso

  publish:
    name: Publish release
    needs: build
    runs-on: ubuntu-24.04

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Download all ISOs
        uses: actions/download-artifact@v4
        with:
          path: output/
          pattern: release-*
          merge-multiple: true

      - name: Generate checksums
        run: |
          cd output
          sha256sum *.iso > SHA256SUMS
          cat SHA256SUMS

      - name: Import GPG signing key
        uses: crazy-max/ghaction-import-gpg@v6
        with:
          gpg_private_key: ${{ secrets.GPG_PRIVATE_KEY }}
          passphrase: ${{ secrets.GPG_PASSPHRASE }}

      - name: Sign checksums
        run: |
          cd output
          gpg --armor --detach-sign SHA256SUMS

      - name: Extract release notes
        id: notes
        run: |
          echo "VERSION=${GITHUB_REF_NAME}" >> $GITHUB_OUTPUT

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          name: "MyDistro ${{ steps.notes.outputs.VERSION }}"
          body: |
            ## MyDistro ${{ steps.notes.outputs.VERSION }}

            ### Downloads
            Verify your download against the SHA256SUMS file using the distro signing key.

            ```bash
            # Import signing key
            gpg --import distro-signing-key.asc

            # Verify
            gpg --verify SHA256SUMS.asc SHA256SUMS
            sha256sum -c SHA256SUMS --ignore-missing
            ```

          files: |
            output/*.iso
            output/SHA256SUMS
            output/SHA256SUMS.asc
            distro-signing-key.asc
          draft: false
          prerelease: ${{ contains(github.ref_name, 'alpha') || contains(github.ref_name, 'beta') || contains(github.ref_name, 'rc') }}
```

---

## Step 5.4 — ARM64 Runner Options

GitHub's hosted `ubuntu-24.04-arm` runners are available on **Team and Enterprise plans**. For open-source public repos, they may be free.

### Option A: GitHub-hosted (simplest)
```yaml
runs-on: ubuntu-24.04-arm
```

### Option B: Self-hosted ARM runner
If you have an ARM machine (e.g., AWS Graviton, Raspberry Pi 5, Oracle ARM free tier):

```bash
# On your ARM host:
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-arm64.tar.gz \
  -L https://github.com/actions/runner/releases/latest/download/actions-runner-linux-arm64-*.tar.gz
tar xzf actions-runner-linux-arm64.tar.gz
./config.sh --url https://github.com/yourorg/my-distro --token YOUR_TOKEN
sudo ./svc.sh install
sudo ./svc.sh start
```

Then in workflow:
```yaml
runs-on: self-hosted
# Or with labels:
runs-on: [self-hosted, linux, arm64]
```

---

## Step 5.5 — Branch Protection Rules

Configure in **Settings → Branches → Add branch protection rule** for `main`:

- [x] Require a pull request before merging
- [x] Require status checks to pass before merging
  - Add: `Build (main) / server / amd64`
  - Add: `Build (main) / desktop / amd64`
  - Add: `Build (main) / developer / amd64`
- [x] Require branches to be up to date before merging
- [x] Do not allow bypassing the above settings

---

## Step 5.6 — Making a Release

```bash
# Merge dev → main via PR (CI must be green)
# Then tag the release:

git checkout main
git pull
git tag -a v1.0 -m "MyDistro 1.0 — initial release"
git push origin v1.0

# This triggers the release workflow
# Monitor at: https://github.com/yourorg/my-distro/actions
```

---

## Step 5.7 — Caching Build Artifacts (Optional Optimization)

live-build downloads Ubuntu packages during every build. Speed up by caching the `build/*/cache/` directory:

Add to each workflow job after checkout:
```yaml
      - name: Cache live-build packages
        uses: actions/cache@v4
        with:
          path: |
            build/*/cache
          key: lb-cache-${{ matrix.edition }}-${{ matrix.arch }}-${{ hashFiles('**/package-lists/*.list') }}
          restore-keys: |
            lb-cache-${{ matrix.edition }}-${{ matrix.arch }}-
```

Note: This cache can grow large (1–3 GB). Set a max size or purge old caches regularly.

---

## Step 5.8 — Commit

```bash
git add .github/ Makefile distro-signing-key.asc
git commit -m "feat: add CI/CD workflows for build, test, and release"
git push origin dev
```

Open a PR from `dev` → `main`. Once the PR workflows pass, merge.

---

## Checklist

- [ ] Distro GPG signing key generated
- [ ] `GPG_PRIVATE_KEY` and `GPG_PASSPHRASE` secrets added to GitHub repo
- [ ] `distro-signing-key.asc` (public key) committed to repo root
- [ ] Makefile updated with `checksums` and `sign` targets, version from git tags
- [ ] `build-dev.yml` workflow created
- [ ] `build-main.yml` workflow created with smoke tests
- [ ] `release.yml` workflow created with GPG signing and GitHub Release creation
- [ ] ARM64 runner strategy decided (GitHub-hosted or self-hosted)
- [ ] Branch protection rules configured for `main`
- [ ] Push to `dev` triggers build — all 6 matrix jobs succeed
- [ ] Open PR dev → main — CI passes — merge
- [ ] Create `v0.1-alpha` tag to test release workflow end-to-end
- [ ] GitHub Release appears with all 6 ISOs + SHA256SUMS + SHA256SUMS.asc
- [ ] Verify checksums: `gpg --verify SHA256SUMS.asc SHA256SUMS`

---

## Next Step

→ [Phase 6: Distribution](PHASE6_DISTRIBUTION.md) (shared)
