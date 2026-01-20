#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def format_mlir(code: str) -> str:
    if not code:
        return ""
    lines = code.split("\n")
    output = []
    for line in lines:
        if re.match(r"^\s*func\.func", line):
            line = line.replace("(", "(\n    ", 1)
            line = line.replace(", %", ",\n    %")
            line = line.replace(") ->", "\n  ) ->")
            line = line.replace(" attributes {", "\n  attributes {")
        output.append(line)
    return "\n".join(output)


def normalize_mlir(code: str) -> str:
    if not code:
        return ""
    return re.sub(r"%[A-Za-z0-9_]+", "%_", code)


def strip_loc(code: str) -> str:
    if not code:
        return ""
    output = []
    i = 0
    length = len(code)
    while i < length:
        idx = code.find("loc(", i)
        if idx == -1:
            output.append(code[i:])
            break
        start = idx
        while start > i and code[start - 1] in " \t":
            start -= 1
        output.append(code[i:start])
        depth = 1
        j = idx + 4
        while j < length and depth:
            char = code[j]
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            j += 1
        if depth != 0:
            output.append(code[idx:])
            break
        i = j
    return "".join(output)


def read_text(path: str) -> str:
    if path == "-":
        return sys.stdin.read()
    return Path(path).read_text(encoding="utf-8")


def write_text(path: str, content: str) -> None:
    if path == "-":
        sys.stdout.write(content)
        return
    Path(path).write_text(content, encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Simplify MLIR for diffing (format func.func and normalize SSA names)."
    )
    parser.add_argument(
        "input",
        nargs="?",
        default="-",
        help="Input MLIR file path, or '-' for stdin",
    )
    parser.add_argument(
        "-o",
        "--output",
        default="-",
        help="Output path, or '-' for stdout",
    )
    parser.add_argument(
        "--no-pretty",
        dest="pretty",
        action="store_false",
        help="Disable func.func pretty-print formatting",
    )
    parser.add_argument(
        "--no-normalize",
        dest="normalize",
        action="store_false",
        help="Disable SSA name normalization",
    )
    parser.add_argument(
        "--no-strip-loc",
        dest="strip_loc",
        action="store_false",
        help="Disable removing loc(...) annotations",
    )
    parser.set_defaults(pretty=True, normalize=True, strip_loc=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    content = read_text(args.input)
    if args.pretty:
        content = format_mlir(content)
    if args.normalize:
        content = normalize_mlir(content)
    if args.strip_loc:
        content = strip_loc(content)
    write_text(args.output, content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
