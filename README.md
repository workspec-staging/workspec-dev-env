# workspec-dev-env

Docker image and Fly.io configuration for WorkSpec workspace machines.

Each workspace machine is a Fly Machine running this image. It provides:
- **Vite dev server** on port 443 — the app being built, visible in the browser
- **workspace-agent gRPC server** on port 50051 — called by the WorkSpec platform to read/write files, run Claude Code tasks, and manage git

---

## Architecture

```
Browser  ──── HTTPS :443 ────▶  Vite dev server   (:8080 internal)
                                  │
                          shared filesystem (/workspace/project)
                                  │
WorkSpec API  ── gRPC :50051 ──▶  workspace-agent  (:3001 internal)
```

The `/workspace` directory is a persistent Fly volume. The git clone and Claude Code session state (`.claude/`) survive machine restarts.

---

## Provisioning a workspace machine

The WorkSpec platform provisions machines via the [Fly Machines API](https://fly.io/docs/machines/api/), not `fly deploy`. Each machine is independent and holds one branch's workspace.

### 1. Generate a GitHub App installation token

The WorkSpec GitHub App must have access to the target repo. Generate a short-lived installation token — used only for the initial `git clone`. After the clone, the volume persists it, so token expiry doesn't affect subsequent boots.

### 2. Create a volume

Each machine needs its own volume:

```bash
fly volumes create workspace_data --region syd --size 10 --app synthesis
# Returns a volume ID, e.g. vol_abc123
```

### 3. Create the machine via Fly Machines API

```http
POST https://api.machines.dev/v1/apps/synthesis/machines
Authorization: Bearer <FLY_API_TOKEN>

{
  "config": {
    "image": "registry.fly.io/synthesis:latest",
    "env": {
      "REPO_URL": "https://github.com/<org>/<repo>",
      "GITHUB_TOKEN": "<installation-token>",
      "WORKSPACE_AGENT_SECRET": "<random-secret>"
    },
    "mounts": [{ "volume": "vol_abc123", "path": "/workspace" }]
  }
}
```

---

## Connecting to the workspace-agent

The gRPC service definition lives in `lib/workspace-proto` in the WorkSpec monorepo. Import `WorkspaceAgentClient` from `@workspace/workspace-proto`.

```ts
import * as grpc from '@grpc/grpc-js';
import { WorkspaceAgentClient } from '@workspace/workspace-proto';

const client = new WorkspaceAgentClient(
  '<machine-hostname>:50051',
  grpc.credentials.createSsl(),
);

// Pass if WORKSPACE_AGENT_SECRET is set on the machine
const meta = new grpc.Metadata();
meta.set('authorization', `Bearer ${secret}`);
```

### RPCs

| RPC | Description |
|---|---|
| `GetFile(path)` | Read a file from the workspace |
| `PutFile(path, content)` | Write a file (mkdir -p on parent) |
| `DeleteFile(path)` | Delete a file |
| `ListFiles(path)` | List directory entries |
| `RunTask(prompt)` → stream | Run Claude Code with `--print --continue`, streams `OutputEvent`, `DoneEvent`, `ErrorEvent` |
| `GitStatus()` | Branch name + porcelain status |
| `GitFetch(githubToken)` | Fetch all remotes — pass a fresh installation token |
| `GitCommit(message)` | Stage all + commit locally (no token needed) |
| `GitPush(branch, githubToken)` | Push HEAD to remote branch — pass a fresh installation token |

**Token handling for git RPCs:** `GitFetch` and `GitPush` require a fresh GitHub App installation token in the request. The WorkSpec platform generates this at call time — tokens are never stored on the machine after the initial clone.

---

## Updating the workspace-agent

The agent bundle is committed to `agent/dist/index.mjs`. To update it after changing `artifacts/workspace-agent` in the WorkSpec monorepo:

```bash
# In the workspec monorepo
pnpm --filter @workspace/workspace-agent run build

# Copy the bundle here
cp artifacts/workspace-agent/dist/index.mjs path/to/workspec-dev-env/agent/dist/index.mjs
```

Then deploy:

```bash
fly deploy --app synthesis
```

Running machines pick up the new image on their next restart, or force one:

```bash
fly machine restart <machine-id> --app synthesis
```

---

## Updating the proto

The `.proto` source lives in `lib/workspace-proto/proto/workspace_agent.proto` in the WorkSpec monorepo. To regenerate TypeScript after changing it:

```bash
# Requires: brew install protobuf
pnpm --filter @workspace/workspace-proto run codegen
```

Generated files in `lib/workspace-proto/src/generated/` are committed. Both the workspace-agent (server) and the WorkSpec API (client) depend on this package.

---

## Local development

To test the entrypoint locally without Fly:

```bash
docker build -t workspec-dev-env .
docker run --rm \
  -e REPO_URL=https://github.com/<org>/<repo> \
  -e GITHUB_TOKEN=<token> \
  -p 8080:8080 \
  -p 3001:3001 \
  workspec-dev-env
```

Vite will be at `http://localhost:8080`. The gRPC agent will be at `localhost:3001` (insecure — no TLS in local mode, use `grpc.credentials.createInsecure()` on the client for local testing).

---

## Machine lifecycle

| Event | What happens |
|---|---|
| First boot | Clones repo using `GITHUB_TOKEN`, runs `pnpm install`, starts Vite + agent |
| Subsequent boots | Resumes from volume (no re-clone), starts Vite + agent |
| Idle | Fly auto-stops the machine after inactivity |
| Wake | Fly auto-starts on next request to port 443 or 50051 |
| git fetch/push | Platform calls `GitFetch`/`GitPush` RPC with a fresh token |
| Token expiry | No impact — tokens are passed per-call, never stored |

## Image contents

- **Node.js 22** (LTS)
- **.NET 10 SDK** + **Aspire CLI** (available for future use)
- **pnpm 10.33.0** (pinned)
- **Claude Code CLI** (`claude`)
- **workspace-agent** at `/app/agent/`
