"""Copy only the files `dart pub publish --dry-run` would publish into an empty directory.

Usage (from the package root):
    dart pub publish --dry-run > /tmp/dry.txt 2>&1
    python3 -I tool/dry_run_copy.py . /tmp/dry.txt <empty dir>/voice_clone_tts

The copy has no .dart_tool and no submodule git data, like the archive pub.dev serves, so building and running
test/real_test.dart there checks that nothing the build hook needs was left out by .pubignore.
"""

import os
import re
import shutil
import sys


def published_files(dry_run_output):
    lines = open(dry_run_output, encoding="utf-8").read().split("\n")
    start = next(i for i, line in enumerate(lines) if line.startswith("Publishing ")) + 1
    stack, files = [], []
    for line in lines[start:]:
        m = re.match(r"^((?:│   |    )*)(?:├── |└── )(.*)$", line)
        if not m:
            break
        depth, name = len(m.group(1)) // 4, m.group(2)
        sized = re.match(r"^(.*) \((?:<?\d+ [KMG]?B)\)$", name)
        stack = stack[:depth]
        if sized:
            files.append("/".join(stack + [sized.group(1)]))
        else:
            stack.append(name)
    return files


def main(src, dry_run_output, dst):
    if os.path.exists(dst) and os.listdir(dst):
        sys.exit(f"{dst} is not empty")
    files = published_files(dry_run_output)
    for f in files:
        target = os.path.join(dst, f)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(os.path.join(src, f), target)
    print(f"{len(files)} files copied to {dst}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
