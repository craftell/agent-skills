#!/usr/bin/env python3
"""Validate sub-agent output against a regex pattern.

Usage: validate_output.py <pattern> <output_file>
Exit codes: 0=valid (at least one match), 1=invalid (no match or multiple ambiguous matches)
Outputs matched keywords to stdout (one per line).
"""

import re
import sys


def main():
    if len(sys.argv) != 3:
        print("Usage: validate_output.py <pattern> <output_file>", file=sys.stderr)
        sys.exit(1)

    pattern = sys.argv[1]
    output_file = sys.argv[2]

    try:
        with open(output_file, "r", encoding="utf-8") as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: File not found: {output_file}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error reading file: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        regex = re.compile(pattern, re.IGNORECASE)
    except re.error as e:
        print(f"Error: Invalid regex pattern: {e}", file=sys.stderr)
        sys.exit(1)

    matches = regex.findall(content)

    if not matches:
        print("Error: No keywords matched", file=sys.stderr)
        sys.exit(1)

    # Normalize matches to uppercase and deduplicate
    unique_keywords = list(dict.fromkeys(m.upper() if isinstance(m, str) else m[0].upper() for m in matches))

    for keyword in unique_keywords:
        print(keyword)

    sys.exit(0)


if __name__ == "__main__":
    main()
