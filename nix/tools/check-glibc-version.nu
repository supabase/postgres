#!/usr/bin/env nu

def parse-version [] {
    split row "." | each { into int }
}

def is-elf []: path -> bool {
    (open --raw $in | bytes at 0..<4) == ("\u{7f}ELF" | into binary)
}

def max-glibc-version [path: path] {
    ^objdump -T $path | complete | get stdout
    | parse -r 'GLIBC_(?<ver>[0-9.]+)' | get ver
    | each { parse-version }
    | sort
    | last
}

# Fails if any file under the given paths requires a newer glibc than max_version.
def main [max_version: string, ...paths: path] {
    let offenders = (
        $paths
        | each { glob $"($in)/**/*" } | flatten
        | where { ($in | path type) == file }
        | where { is-elf }
        | par-each { |f| { file: $f, version: (max-glibc-version $f) } }
        | compact version
        | where version > ($max_version | parse-version)
    )

    if ($offenders | is-empty) {
        print $"glibc version OK \(<= ($max_version)\)"
        exit 0
    }

    print $offenders
    exit 1
}
