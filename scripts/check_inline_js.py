#!/usr/bin/env python3
"""Extract inline <script> blocks from HTML files and syntax-check them with node."""
import re
import subprocess
import sys
import tempfile

def main():
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} FILE.html [FILE.html ...]", file=sys.stderr)
        return 2

    failed = False
    for path in sys.argv[1:]:
        with open(path, encoding="utf-8") as f:
            html = f.read()
        scripts = re.findall(r"<script[^>]*>(.*?)</script>", html, re.S)
        if not scripts:
            print(f"OK   {path} (no inline scripts)")
            continue
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as tmp:
            tmp.write("\n;\n".join(scripts))
            tmp_path = tmp.name
        result = subprocess.run(["node", "--check", tmp_path], capture_output=True, text=True)
        if result.returncode == 0:
            print(f"OK   {path} ({len(scripts)} script block(s))")
        else:
            failed = True
            print(f"FAIL {path}")
            print(result.stderr, file=sys.stderr)

    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
