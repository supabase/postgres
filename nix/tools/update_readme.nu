#!/usr/bin/env nu

# Load required data
def load_flake [] {
    nix flake show --json --all-systems | from json
}

def find_index [list: list<any>, value: any] {
    let enumerated = ($list | enumerate)
    let found = ($enumerated | where item == $value | first)
    if ($found | is-empty) {
        -1
    } else {
        $found.index
    }
}

def get_systems [flake_json] {
    $flake_json | get packages | columns
}

def get_postgres_versions [flake_json] {
    let packages = ($flake_json | get packages | get aarch64-linux)
    
    # Get available versions from postgresql packages
    let available_versions = ($packages 
        | columns 
        | where {|col| 
            # Match exact postgresql_<number> or postgresql_orioledb-<number>
            $col =~ "^postgresql_\\d+$" or $col =~ "^postgresql_orioledb-\\d+$"
        }
        | each {|pkg_name|
            let is_orioledb = ($pkg_name =~ "orioledb")
            let pkg_info = ($packages | get $pkg_name)
            let version = if $is_orioledb {
                $pkg_info.name | str replace "postgresql-" "" | split row "_" | first  # Get "17" from "postgresql-17_5"
            } else {
                $pkg_info.name | str replace "postgresql-" "" | split row "." | first  # Get "15" from "postgresql-15.8"
            }
            {
                version: $version,
                is_orioledb: $is_orioledb,
                name: $pkg_info.name
            }
        }
    )

    $available_versions | uniq | sort-by version
}

def get_src_url [pkg_attr] {
    let result = (do { nix eval $".#($pkg_attr).src.url" } | complete)
    if $result.exit_code == 0 {
        $result.stdout | str trim | str replace -a '"' ''  # Remove all quotes
    } else {
        null
    }
}

def get_extension_info [flake_json, pg_info] {
    let major_version = ($pg_info.version | split row "." | first)
    let version_prefix = if $pg_info.is_orioledb {
        "psql_orioledb-" + $major_version + "/exts/"
    } else {
        "psql_" + $major_version + "/exts/"
    }
    
    print $"Looking for extensions with prefix: ($version_prefix)"
    
    let sys_packages = ($flake_json | get packages | get aarch64-linux)
    let ext_names = ($sys_packages 
        | columns 
        | where {|col| $col =~ $"^($version_prefix)"}
    )
    print $"Found extensions: ($ext_names | str join ', ')"
    
    let all_exts = ($ext_names | each {|ext_name| 
        let ext_info = ($sys_packages | get $ext_name)
        let name = ($ext_name | str replace $version_prefix "")
        let version = if $name == "orioledb" {
            $ext_info.name  # Use name directly for orioledb
        } else if ($ext_info.name | str contains "-") {
            $ext_info.name | split row "-" | last
        } else {
            $ext_info.name
        }
        let src_url = (get_src_url $ext_name)
        {
            name: $name,
            version: $version,
            description: $ext_info.description,
            url: $src_url
        }
    })
    
    $all_exts | sort-by name
}

def create_version_link [pg_info] {
    if $pg_info.is_orioledb {
        let display = $"orioledb-($pg_info.name)"
        let url = "https://github.com/orioledb/orioledb"
        $"- ✅ Postgres [($display)]\(($url)\)"
    } else {
        let major_version = ($pg_info.version | split row "." | first)
        let url = $"https://www.postgresql.org/docs/($major_version)/index.html"
        $"- ✅ Postgres [($pg_info.name)]\(($url)\)"  # Use full version number
    }
}

def create_ext_table [extensions, pg_info] {
    let header_version = if $pg_info.is_orioledb {
        $"orioledb-($pg_info.version)"  # Add orioledb prefix for orioledb versions
    } else {
        $pg_info.version
    }
    
    let header = [
        "",  # blank line for spacing
        $"### PostgreSQL ($header_version) Extensions",
        "| Extension | Version | Description |",
        "| ------------- | :-------------: | ------------- |"
    ]
    
    let rows = ($extensions | each {|ext|
        let name = $ext.name
        let version = $ext.version
        let desc = $ext.description
        let url = $ext.url  # Get URL from extension info
        
        $"| [($name)]\(($url)\) | [($version)]\(($url)\) | ($desc) |"
    })
    
    $header | append $rows
}

def update_readme [] {
    let flake_json = (load_flake)
    let readme_path = ([$env.PWD "README.md"] | path join)
    let readme = (open $readme_path | lines)
    let pg_versions = (get_postgres_versions $flake_json)
    
    # Find section indices
    let features_start = ($readme | where $it =~ "^## Primary Features" | first)
    let features_end = ($readme | where $it =~ "^## Extensions" | first)
    let features_start_idx = (find_index $readme $features_start)
    let features_end_idx = (find_index $readme $features_end)
    
    if $features_start_idx == -1 or $features_end_idx == -1 {
        error make {msg: "Could not find Features sections"}
    }
    
    # Update Primary Features section
    let features_content = [
        ($pg_versions | each {|version| create_version_link $version} | str join "\n")
        "- ✅ Ubuntu 20.04 (Focal Fossa)."
        "- ✅ [wal_level](https://www.postgresql.org/docs/current/runtime-config-wal.html) = logical and [max_replication_slots](https://www.postgresql.org/docs/current/runtime-config-replication.html) = 5. Ready for replication."
        "- ✅ [Large Systems Extensions](https://github.com/aws/aws-graviton-getting-started#building-for-graviton-and-graviton2). Enabled for ARM images."
    ]

    # Find extension section indices
    let ext_start = ($readme | where $it =~ "^## Extensions" | first)
    let ext_start_idx = (find_index $readme $ext_start)
    
    # Find next section after Extensions or use end of file
    let next_section_idx = ($readme 
        | enumerate 
        | where {|it| $it.index > $ext_start_idx and ($it.item =~ "^## ")} 
        | first
        | get index
        | default ($readme | length)
    )
    
    if $ext_start_idx == -1 {
        error make {msg: "Could not find Extensions section"}
    }

    # Create extension sections content
    let ext_sections_content = ($pg_versions | each {|version|
        let extensions = (get_extension_info $flake_json $version)
        create_ext_table $extensions $version
    } | flatten)

    # Combine sections, removing duplicate headers
    let before_features = ($readme 
        | range (0)..($features_start_idx)
        | where {|line| not ($line =~ "^## Primary Features")}
    )
    let features_header = ($readme | get $features_start_idx)
    let between_sections = ($readme 
        | range ($features_end_idx)..($ext_start_idx)
        | where {|line| 
            not ($line =~ "^## Primary Features" or $line =~ "^## Extensions")
        }
    )
    let ext_header = ($readme | get $ext_start_idx)
    let after_ext = ($readme | range ($next_section_idx)..($readme | length))

    let output = ($before_features 
        | append $features_header
        | append $features_content
        | append $between_sections
        | append $ext_header
        | append $ext_sections_content
        | append $after_ext
        | str join "\n")
    
    $output | save --force $readme_path
}

# Main execution
update_readme
