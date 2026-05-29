# slock-mac-mini-setup

Standard Mac mini deployment for Ecoya Consulting clients. Installs everything needed to run Slock + agents at a client site.

## Quick Start

On a fresh macOS Mac mini, run:

```bash
curl -fsSL https://raw.githubusercontent.com/Jacky040124/slock-mac-mini-setup/main/bootstrap.sh | bash
```

That's it. Takes 10-15 minutes depending on network.

## What it installs (14 items)

**System prerequisites**
- Homebrew · Xcode Command Line Tools · Git · Node.js · uv

**Terminal**
- Ghostty

**Slock + agent runtime**
- Slock daemon · Claude Code · OpenAI Codex · Beeper · Obsidian

**Browser + automation**
- Google Chrome · OpenCLI

**Remote support**
- Tailscale

## What it does NOT do (manual steps after install)

The installer prints these at the end. They require human interaction:

1. **Chrome accounts** — log in to client's XHS / IG / Gmail / WhatsApp Web / WeChat (2FA needs client)
2. **Tailscale** — join Ecoya Consulting tailnet (auth key from `tailscale up`)
3. **Slock workspace** — `slock` and join the assigned server / workspace
4. **Obsidian vault** — open client's workspace folder as vault
5. **Beeper** — log in and connect client's IM accounts (2FA needs client)

## Files

| File | Purpose |
|------|---------|
| `bootstrap.sh` | One-liner entry — clones this repo and runs install.sh |
| `install.sh` | Main installer — Homebrew + Xcode CLI + Brewfile + npm globals |
| `Brewfile` | Brew formulas + casks (9 of the 14 items) |

## Manual fallback

If `curl | bash` is not preferred:

```bash
git clone https://github.com/Jacky040124/slock-mac-mini-setup.git
cd slock-mac-mini-setup
bash install.sh
```

## Updating an existing client machine

```bash
cd ~/slock-mac-mini-setup
git pull
bash install.sh   # idempotent — skips already-installed items
```

## Maintained by

Ecoya Consulting Inc · Jacky Zhong · zhongzhenyu190@gmail.com
