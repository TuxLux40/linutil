# Fork Roadmap

Deferred items and known gaps tracked here.

## Agent Skills

- [ ] **Grok CLI skills support** — `npx skills` does not yet have a Grok agent target.
  Once `grok` gains a skills directory (analogous to `~/.claude/skills/`), update
  `agent-skills-setup.sh` to include `-a 'grok'` or rely on `--agent '*'` picking it up.
  Track: [skills.sh](https://www.skills.sh) release notes.

## TUI Dashboard / tui-shop

- [ ] **Evaluate tui-shop upstream** (`TuxLux40/tui-shop`, forked from `Gcat101/tui-shop`).
  Upstream last active ~2022, Python-based. Decide: modernise with uv + updated sources,
  or write a lightweight linutil script that installs tools from the curated list directly.
  Reference list: `HANDOFF-tui-shop.md`.

- [ ] **Wire tui-shop into linutil** — add `applications-setup/AI/tui-shop-setup.sh` entry
  once the above is resolved.

## Hardware

- [ ] **TRCC Linux** — waiting on upstream PRs to merge into
  `TuxLux40/thermalright-trcc-linux`. Once merged, update `hardware/trcc-setup.sh`
  to point at upstream `ChrisTitusTech`-style canonical URL if applicable.

## Misc

- [ ] **Notion / Cloudflare agent skills** — `agent-skills-setup.sh` installs these via SSH.
  If those repos ever go public HTTPS, remove the `ssh:` prefix.
