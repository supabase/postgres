import sys

# glibc ignores spaces and punctuation at the first comparison level, so the
# affixes exercise tie-breaking, not only primary weights.
AFFIXES = ("{c}", "{c}B", "B{c}", "{c} ", " {c}", "{c}.", "3{c}", "{c}{c}")

for cp in range(0x20, 0x30000):
    if 0x7F <= cp <= 0x9F or 0xD800 <= cp <= 0xDFFF:
        continue
    for affix in AFFIXES:
        sys.stdout.write(affix.format(c=chr(cp)) + "\n")
