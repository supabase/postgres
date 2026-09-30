# drvPath captures any input change (source, patches, deps, build steps),
# not just a bumped version string, and evaluating it is pure -- no
# substituter queries, no downloads, no builds.
{ dir, system }:
let
  flake = builtins.getFlake dir;
  isDrv = v: (v.type or "") == "derivation";
  collect =
    prefix: set:
    builtins.concatLists (
      map (
        n:
        let
          v = set.${n};
        in
        if isDrv v then
          [
            {
              name = prefix + n;
              drvPath = v.drvPath;
            }
          ]
        else if builtins.isAttrs v then
          collect (prefix + n + ".") v
        else
          [ ]
      ) (builtins.attrNames set)
    );
in
builtins.listToAttrs (
  map (e: {
    inherit (e) name;
    value = e.drvPath;
  }) (collect "" flake.legacyPackages.${system})
)
