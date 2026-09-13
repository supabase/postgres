# Fails if any file under the given paths requires a glibc symbol version
# above the allowed floor.

def ver-key [ver: string] {
    $ver | split row "." | each { into int }
}

def is-elf []: string -> bool {
    ($in | path type) == file and (open --raw $in | bytes at 0..<4) == 0x[7f454c46]
}

def main [max_allowed: string, ...paths: string] {
    let max_key = (ver-key $max_allowed)

    let offenders = (
        $paths
        | each { |p| glob $"($p)/**/*" }
        | flatten
        | where { is-elf }
        | par-each { |file|
            let versions = (^objdump -T $file | complete | get stdout | parse -r 'GLIBC_(?<ver>[0-9.]+)' | get ver)
            if ($versions | is-empty) {
                null
            } else {
                { file: $file, version: ($versions | sort-by { |v| ver-key $v } | last) }
            }
        }
        | compact
        | where { |h| (ver-key $h.version) > $max_key }
    )

    if ($offenders | is-empty) {
        print $"glibc floor OK \(<= ($max_allowed)\)"
        exit 0
    }

    print $offenders
    exit 1
}
