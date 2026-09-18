"""Supply runtime headers in memory to upstream mcp-proxy, never through argv."""

import asyncio
import json
import logging
import os
import re
import sys

from mcp_proxy.streamablehttp_client import run_streamablehttp_client


def resolve_headers(templates, environment):
    def replace(match):
        value = environment.get(match.group(1))
        if not value:
            raise ValueError("Missing required MCP credential")
        return value

    return {
        name: re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", replace, value)
        for name, value in templates.items()
    }


def main():
    # Protocol libraries may log exception details. Keep failures value-free;
    # stdout belongs exclusively to the MCP protocol.
    logging.disable(logging.CRITICAL)
    try:
        with open(sys.argv[1]) as handle:
            config = json.load(handle)
        headers = resolve_headers(config["headers"], os.environ)
        asyncio.run(run_streamablehttp_client(config["url"], headers=headers))
    except Exception:
        print("MCP HTTP bridge failed; check authentication and endpoint availability", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
