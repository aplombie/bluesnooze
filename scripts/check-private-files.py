#!/usr/bin/env python3
"""Reject local-only paths in the index or reachable commit history."""
import subprocess
import sys


def git(*args):
    return subprocess.check_output(["git", *args])


def private(path):
    parts = path.split("/")
    return (any(p in {"AGENTS.md", "CLAUDE.md", ".agent", ".claude", ".codex", ".agents"} for p in parts)
            or parts[0] == "planning")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--staged":
        paths = git("ls-files", "--cached", "-z").decode().split("\0")
    elif len(sys.argv) >= 3 and sys.argv[1] == "--history":
        paths = [line.partition(" ")[2] for line in
                 git("rev-list", "--objects", *sys.argv[2:]).decode().splitlines()]
    else:
        sys.exit("Usage: check-private-files.py --staged | --history REV...")
    rejected = sorted({path for path in paths if path and private(path)})
    if rejected:
        print("Private working files must stay local; blocked paths:", file=sys.stderr)
        for path in rejected:
            print("  " + path, file=sys.stderr)
        return 1
    print("Private-path check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
