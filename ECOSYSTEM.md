# Ecosystem

This repo is part of the [Bernard Bootstrap](https://github.com/mister-bernard/bernard-bootstrap) ecosystem.

## Role
The `cc` command — CLAUDE.md synthesizer, tmux session launcher, and role presets for Claude Code.

## Related repos
| Repo | Role |
|------|------|
| [bernard-bootstrap](https://github.com/mister-bernard/bernard-bootstrap) | Master entry point — templates, playbooks, provisioning |
| [bernard-skills](https://github.com/mister-bernard/bernard-skills) | Skill packages (voice, stego, Twitter, SMS) |
| **cc-bridge** (private) | Persistent CC sessions as OpenAI-compatible HTTP endpoint |
| **openclaw-1** (private) | Modified OpenClaw fork |

## Setup
To clone all ecosystem repos at once:
```
git clone https://github.com/mister-bernard/bernard-bootstrap.git
cd bernard-bootstrap
bash setup-ecosystem.sh
```
