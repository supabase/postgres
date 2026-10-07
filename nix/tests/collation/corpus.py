"""Write the collation test corpus to stdout, one string per line.

Every code point from U+0020 to U+2FFFF, except C1 controls and surrogates,
appears alone and with affixes. glibc collation ignores spaces and punctuation
at the first level, so the affixes exercise tie-breaking, not only primary
weights. The corpus depends on nothing but this file.
"""

import sys

AFFIXES = ("{c}", "{c}B", "B{c}", "{c} ", " {c}", "{c}.", "3{c}", "{c}{c}")


def codepoints():
    for cp in range(0x20, 0x30000):
        if 0x7F <= cp <= 0x9F or 0xD800 <= cp <= 0xDFFF:
            continue
        yield chr(cp)


def main():
    out = sys.stdout
    for c in codepoints():
        for affix in AFFIXES:
            out.write(affix.format(c=c))
            out.write("\n")


if __name__ == "__main__":
    main()
