---
name: token-usage-codeburn
description: How to measure Claude Code token usage here (CodeBurn via Node 23) and what the 02.10.2026 report showed
metadata:
  node_type: memory
  type: reference
  originSessionId: fbd0ffdf-a000-4fd0-bf3c-23ee323016e7
  modified: 2026-10-02T08:55:52.275Z
---

User is on a Claude subscription (not API key), so CodeBurn's dollars are API-equivalent volume, not a bill.

Run CodeBurn without a global install (system node is v20, it needs 22.13+), and always pass `--provider claude`, because scanning ~38 GB of Cursor data takes over 5 minutes:

`PATH=/usr/local/Cellar/node/23.11.0/bin:$PATH npx --yes codeburn@0.9.25 overview -p all --provider claude --project ragdoll --no-color`

Report from 02.10.2026, covering 18.09–02.10:
- About $1,376 API-equivalent and about 2.4B tokens; 96% of the tokens were cache reads.
- 3 tasks with large multi-agent workflows accounted for 94% of the total:
  - the 18.09 audit: $698, 80 subagents
  - doll kit v2: $312, 83 subagents
  - the 28.09 memory review: $283, 14 subagents
- Ordinary sessions cost $1–35 each.

The lever for limits is workflow size, not config. Don't apply CodeBurn's MCP-removal advice: claude-in-chrome and ccd_* belong to the desktop app. Headroom, Ponytail and Graphify were rejected; see [[project-essence]].
