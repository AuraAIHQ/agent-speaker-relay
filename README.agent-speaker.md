# Agent Speaker Relay

Fork of [strfry](https://github.com/hoytech/strfry) - Nostr relay customized for Agent Speaker ecosystem.

## Branch Strategy

```
main (protected) ───────► sync with upstream/hoytech/strfry
      │
      ▼
agent-speaker (default) ► our customizations
      │
      ├──► feature/xxx   ► feature branches
      │
      └──► release/vx.x  ► release branches
```

| Branch | Purpose | Protected |
|--------|---------|-----------|
| `main` | Sync with upstream strfry | Yes |
| `agent-speaker` | Default branch with our changes | Yes |
| `feature/*` | Feature development | No |
| `release/*` | Release preparation | Yes |

## Quick Start

### Docker (Recommended)

```bash
docker run -d \
  --name agent-speaker-relay \
  -p 7777:7777 \
  -v $(pwd)/data:/app/strfry-db \
  -v $(pwd)/strfry.conf:/app/strfry.conf \
  ghcr.io/mushroomdao/agent-speaker-relay:latest
```

### Build from Source

```bash
# Clone
git clone https://github.com/mushroomdao/agent-speaker-relay.git
cd agent-speaker-relay

# Build
git submodule update --init
mkdir build
cd build
cmake ..
make -j4

# Run
./strfry --config ../strfry.conf
```

## Customization

### Current Differences from Upstream

- Pre-configured for Agent Speaker (Kind 30078 support)
- Optimized for small teams (2-50 agents)
- Default retention: 30 days

### Planned Customizations

- [ ] Agent verification plugin
- [ ] Rate limiting per pubkey
- [ ] Custom API endpoints for stats
- [ ] Webhook support for agent events

## Sync with Upstream

```bash
# Add upstream remote
git remote add upstream https://github.com/hoytech/strfry.git

# Fetch upstream
git fetch upstream

# Sync main branch
git checkout main
git merge upstream/main
git push origin main

# Rebase agent-speaker branch
git checkout agent-speaker
git rebase main
git push origin agent-speaker --force-with-lease
```

## License

Same as upstream: GPL-3.0
