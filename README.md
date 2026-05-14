# workspec-dev-env

The WorkSpec workstation image — a Linux environment with the toolchain needed to work on any WorkSpec project.

## What's in the image

- **Node.js 22** (LTS)
- **.NET 10 SDK**
- **Aspire CLI** (`aspire run`, `aspire run --isolated`, `aspire deploy`)
- **Claude Code CLI** (`claude`)
- **git**

## Build locally

```bash
docker build -t workspec-dev-env .
```

## Verify tools

```bash
docker run --rm workspec-dev-env git --version
docker run --rm workspec-dev-env node --version
docker run --rm workspec-dev-env aspire --version
docker run --rm workspec-dev-env claude --version
```

## Run (interactive shell)

```bash
docker run --rm -it workspec-dev-env bash
```

## Deploy to Fly

```bash
fly launch --copy-config --no-deploy
fly deploy
```

SSH into the running machine:

```bash
fly ssh console -a workspec-dev-env-smoke
```

## What this is not

This image has no project code and serves no HTTP traffic. It is a workstation you exec into. Project code, volumes, and bootstrap scripts are Phase 2.
