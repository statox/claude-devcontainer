#!/bin/bash
set -euo pipefail

# Root provisioning for the agent container.
# The host scripts run it with `compose exec -u root`.
#
# Installs the repo's [bootstrap.packages].
# Root trust decisions persist in the mise-root-state volume. dev can't write them.
#
# Runs on every `ccc` and `ccc-rebuild`. Keep it idempotent and fast.
cd /workdir

# Explain the trust prompt when the repo config is untrusted
if mise trust --show 2>/dev/null | grep -q ': untrusted$'; then
    echo "==> Trust prompt 1/2: system packages, as root."
    echo "    This repo's mise config is new or changed."
    echo "    Trusting it installs its [bootstrap.packages] as root."
    echo "    Prompt 2/2 follows for its [tools], as dev."
    echo "    Root and dev trust are separate. The agent can't approve root installs."
fi
mise bootstrap packages apply
