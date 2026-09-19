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
    except Exception as exc:
        # Error strings can contain request headers. Log only exception classes
        # and HTTP status codes so startup failures remain diagnosable.
        def describe(error):
            if isinstance(error, BaseExceptionGroup):
                return ",".join(describe(child) for child in error.exceptions)
            status = getattr(getattr(error, "response", None), "status_code", None)
            code = getattr(error, "errno", None)
            detail = type(error).__name__
            if isinstance(status, int):
                detail += f"({status})"
            if isinstance(code, int):
                detail += f"(errno={code})"
            message = str(error).lower()
            if any(word in message for word in ("nodename", "name or service", "dns", "resolve", "host")):
                detail += "(dns)"
            elif "refused" in message:
                detail += "(refused)"
            elif "timed out" in message or "timeout" in message:
                detail += "(timeout)"
            elif "permission" in message or "operation not permitted" in message:
                detail += "(permission)"
            elif "unreachable" in message:
                detail += "(unreachable)"
            elif "certificate" in message or "ssl" in message:
                detail += "(tls)"
            elif "proxy" in message:
                detail += "(proxy)"
            elif "all connection attempts" in message:
                detail += "(all-attempts)"
            if error.__cause__ is not None:
                detail += ">" + describe(error.__cause__)
            return detail

        detail = describe(exc)
        print(f"MCP HTTP bridge failed: {detail}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
