# nix-eval-jobs-shaped JSONL (slurped) -> GitHub Actions build matrices for one system.
#
#   jq -r -s --arg system x86_64-linux -f github-matrix.jq jobs.jsonl
#
# Evaluation errors are printed as ::error annotations and exit 1.

def labels(l): { labels: [l] };

def runner:
  (.requiredSystemFeatures // []) as $f
  | (.system | split("-")) as [$arch, $os]
  | ($f | any(. == "apple-virt" or . == "kvm")) as $virt
  | ($f | any(. == "big-parallel")) as $large
  | if   $virt and $os == "darwin"    then { group: "self-hosted-runners-nix", labels: ["aarch64-darwin"] }
    elif $virt and $arch == "aarch64" then labels("arm-native-runner")
    elif $virt                        then labels("blacksmith-16vcpu-ubuntu-2404")
    elif $os == "darwin"              then labels(if $large then "blacksmith-12vcpu-macos-26" else "blacksmith-6vcpu-macos-26" end)
    elif $arch == "aarch64"           then labels(if $large then "blacksmith-32vcpu-ubuntu-2404-arm" else "blacksmith-8vcpu-ubuntu-2404-arm" end)
    else                                   labels(if $large then "blacksmith-32vcpu-ubuntu-2404" else "blacksmith-8vcpu-ubuntu-2404" end)
    end;

def job:
  (.attr | split(".")) as $p
  | { attr, name, system, runs_on: runner }
  + (if $p[-2] == "exts" then { postgresql_version: ($p[-3] | split("_")[-1]) } else {} end);

# one annotation per distinct error message
def annotations:
  group_by(.error)
  | map(
      "::error title=Nix Evaluation Error::"
      + (if length > 1 then "Affected attributes (\(length)): \(map(.attr) | join(", "))"
         else "Attribute: \(.[0].attr)" end)
      + "%0A%0A" + (.[0].error | gsub("\n"; "%0A"))
    )
  | .[];

def entries(kind):
  map(select(.attr | startswith(kind + ".")))
  | if length > 0 then . else
      [ { attr: "", name: "no \(if kind == "checks" then "checks" else "packages" end) to build",
          system: $system, runs_on: labels("ubuntu-latest") } ]
    end
  | { include: . };

# first occurrence wins, input order preserved (unique_by would sort)
def dedupe: reduce .[] as $j ([]; if any(.[]; .drvPath == $j.drvPath) then . else . + [$j] end);

def matrix:
  dedupe
  | map(select(.cacheStatus == "notBuilt"))
  # no runners that can run the NixOS VM tests on darwin
  | map(select((.system == "aarch64-darwin" and ((.requiredSystemFeatures // []) | any(. == "nixos-test"))) | not))
  | map(job)
  | { packages: entries("legacyPackages"), checks: entries("checks") };

map(select(.error != null)) as $errors
| if ($errors | length) > 0 then ($errors | annotations), ("" | halt_error(1))
  else map(select(.error == null)) | matrix end
