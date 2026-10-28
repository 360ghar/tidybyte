#!/usr/bin/env python3
"""End-to-end test for the tidybyte-mcp server over stdio JSON-RPC.

Builds a small duplicate fixture, drives the real server binary through the
full agent flow — initialize, scan, inspect, mandatory dry-run, confirmed
execute, history, confirmed undo — and verifies the on-disk effects of an
APFS fold and its undo via inode/identity checks.

Usage: Scripts/mcp-e2e.py [path-to-tidybyte-mcp-binary]
"""

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile

BINARY = sys.argv[1] if len(sys.argv) > 1 else ".build/debug/tidybyte-mcp"
OLD_TS = 1700000000  # any timestamp outside the fold's quiet period


class MCPClient:
    def __init__(self, proc):
        self.proc = proc
        self.next_id = 0

    def request(self, method, params=None):
        self.next_id += 1
        payload = {"jsonrpc": "2.0", "id": self.next_id, "method": method}
        if params is not None:
            payload["params"] = params
        self.proc.stdin.write(json.dumps(payload) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError(f"server closed the stream during {method}")
        return json.loads(line)

    def call(self, tool, arguments=None):
        response = self.request("tools/call", {"name": tool, "arguments": arguments or {}})
        result = response["result"]
        text = result["content"][0]["text"]
        return result.get("isError", False), text


def identity(path):
    st = os.lstat(path)
    return (st.st_dev, st.st_ino)


def main():
    if not os.path.exists(BINARY):
        print(f"FAIL: binary not found at {BINARY}; run swift build first")
        return 2

    root = tempfile.mkdtemp(prefix="mcp-e2e-")
    failures = []

    def check(name, condition, detail=""):
        status = "ok" if condition else "FAIL"
        print(f"[{status}] {name}{(' — ' + detail) if detail and not condition else ''}")
        if not condition:
            failures.append(name)

    try:
        a = os.path.join(root, "a")
        b = os.path.join(root, "b")
        os.makedirs(a)
        os.makedirs(b)
        payload = os.urandom(200_000)
        first = os.path.join(a, "blob.bin")
        second = os.path.join(b, "blob.bin")
        with open(first, "wb") as f:
            f.write(payload)
        shutil.copyfile(first, second)
        for path in (first, second):
            os.utime(path, (OLD_TS, OLD_TS))
        before_first = identity(first)
        before_second = identity(second)

        env = dict(os.environ)
        db_path = os.path.join(root, "mcp-e2e.sqlite")
        env["TIDYBYTE_DB"] = db_path
        proc = subprocess.Popen(
            [BINARY], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            text=True, bufsize=1, env=env,
        )
        client = MCPClient(proc)

        init = client.request("initialize", {"protocolVersion": "2024-11-05"})
        check("initialize echoes protocol", init["result"]["protocolVersion"] == "2024-11-05")

        tools = client.request("tools/list")["result"]["tools"]
        names = [t["name"] for t in tools]
        check("tools/list has the full surface",
              names == ["scan", "list_findings", "show_plan", "check_finding", "execute", "history", "undo"],
              str(names))

        is_error, text = client.call("scan", {"paths": [root]})
        check("scan succeeds", not is_error, text)

        is_error, text = client.call("list_findings", {"query": "duplicate"})
        check("list_findings shows a duplicate group", not is_error and "duplicate" in text.lower(), text)

        is_error, text = client.call("execute")
        check("execute without confirm is a dry run",
              not is_error and "Dry run" in text and "confirm: true" in text, text)

        is_error, text = client.call("execute", {"confirm": True})
        check("confirmed execute succeeds", not is_error, text)

        after_first = identity(first)
        after_second = identity(second)
        check("fold keeps the keeper inode", after_first == before_first)
        check("fold replaces the duplicate inode", after_second != before_second)
        with open(second, "rb") as f:
            check("folded file keeps its contents", f.read() == payload)

        is_error, text = client.call("history")
        check("history lists the operation", not is_error and "clone" in text.lower(), text)

        import re
        # Match the operation that touched THIS run's fixture — earlier runs
        # may have left records whose paths no longer exist.
        match = re.search(rf"op \[([0-9a-fA-F-]+)\] unfoldClone {re.escape(second)} ", text)
        check("history exposes an operation id", match is not None, text)
        if match:
            op_id = match.group(1)
            is_error, text = client.call("undo", {"operation_log_id": op_id})
            check("undo without confirm is a dry run",
                  not is_error and "Dry run" in text and "confirm: true" in text, text)
            is_error, text = client.call("undo", {"operation_log_id": op_id, "confirm": True})
            check("confirmed undo succeeds", not is_error, text)

            undone_second = identity(second)
            check("undo gives the file a fresh private inode", undone_second != after_second)
            with open(second, "rb") as f:
                check("unfolded file keeps its contents", f.read() == payload)
    finally:
        try:
            proc.kill()
        except Exception:
            pass
        shutil.rmtree(root, ignore_errors=True)

    if failures:
        print(f"\nmcp-e2e: {len(failures)} check(s) failed: {failures}")
        return 1
    print("\nmcp-e2e: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
