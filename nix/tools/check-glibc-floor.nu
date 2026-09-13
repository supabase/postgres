# Fails if any file under the given paths requires a glibc symbol version
# above the allowed floor.

def "ver-key" [ver: string] {
    $ver | split row "." | each { into int }
}

def main [max_allowed: string, ...paths: string] {
    let max_key = (ver-key $max_allowed)

    let offenders = (
        $paths
        | each { |p| glob ($p + "/**/*") }
        | flatten
        | where { |f| ($f | path type) == file }
        | each { |f|
            let res = (do { ^objdump -T $f } | complete)
            let vers = (if $res.exit_code == 0 {
                $res.stdout | parse -r 'GLIBC_(?<ver>[0-9.]+)' | get ver
            } else {
                []
            })
            if ($vers | is-empty) {
                null
            } else {
                { file: $f, ver: ($vers | sort-by { |v| ver-key $v } | last) }
            }
        }
        | compact
        | where { |h| (ver-key $h.ver) > $max_key }
    )

    if ($offenders | is-empty) {
        print $"glibc floor OK \(<= ($max_allowed)\)"
        exit 0
    }

    for o in $offenders {
        print $"glibc floor ($o.ver) exceeds max allowed ($max_allowed) in ($o.file)"
    }
    exit 1
}
