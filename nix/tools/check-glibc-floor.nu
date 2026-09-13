# Fails if any file under the given paths requires a glibc symbol version
# above the allowed floor.

def "ver-key" [ver: string] {
    $ver | split row "." | each { into int }
}

def main [max_allowed: string, ...paths: string] {
    let hits = (
        $paths
        | each { |p| glob ($p + "/**/*") }
        | flatten
        | where { |f| ($f | path type) == file }
        | each { |f|
            let res = (do { ^objdump -T $f } | complete)
            if $res.exit_code != 0 {
                []
            } else {
                $res.stdout | parse -r 'GLIBC_(?<ver>[0-9.]+)' | each { |m| { ver: $m.ver, file: $f } }
            }
        }
        | flatten
    )

    if ($hits | is-empty) {
        exit 0
    }

    let worst = (
        $hits
        | insert key { |h| ver-key $h.ver }
        | sort-by key
        | last
    )

    print $"glibc floor: ($worst.ver) \(max allowed: ($max_allowed)\) — ($worst.file)"

    if (ver-key $worst.ver) > (ver-key $max_allowed) {
        print $"glibc floor ($worst.ver) exceeds max allowed ($max_allowed) in ($worst.file)"
        exit 1
    }
}
