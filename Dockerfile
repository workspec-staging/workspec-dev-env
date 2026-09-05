FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    git \
    ca-certificates \
    gnupg \
    apt-transport-https \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# .NET 10 SDK via Microsoft apt repository
RUN curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb \
    -o /tmp/packages-microsoft-prod.deb \
    && dpkg -i /tmp/packages-microsoft-prod.deb \
    && rm /tmp/packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y dotnet-sdk-10.0 \
    && rm -rf /var/lib/apt/lists/*

# Aspire CLI standalone binary
RUN curl -sSL https://aspire.dev/install.sh | bash
ENV PATH="$PATH:/root/.aspire/bin"

# pnpm via corepack (required by Aspire.Hosting.JavaScript restore)
# Pin version to match local dev where onlyBuiltDependencies fix is verified
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Pre-cache Aspire NuGet packages so first-boot restore is instant.
# Versions must match fullstack-typescript-project/aspire.config.json.
RUN mkdir -p /tmp/aspire-warm && \
    printf '{"appHost":{"path":"apphost.ts","language":"typescript/nodejs"},"sdk":{"version":"13.2.0"},"packages":{"Aspire.Hosting.JavaScript":"13.2.0"},"profiles":{}}' \
        > /tmp/aspire-warm/aspire.config.json && \
    printf 'import { createBuilder } from "./.modules/aspire.js"; const b = await createBuilder(); await b.build().run();' \
        > /tmp/aspire-warm/apphost.ts && \
    cd /tmp/aspire-warm && aspire restore && \
    rm -rf /tmp/aspire-warm

WORKDIR /workspace

# Workspace agent — gRPC server that exposes file CRUD, Claude Code task
# execution, and git operations to the WorkSpec platform.
COPY agent/ /app/agent/
RUN cd /app/agent && npm install --production

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
