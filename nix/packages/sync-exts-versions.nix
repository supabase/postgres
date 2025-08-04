{
  runCommand,
  jq,
  yq,
  nix-editor,
  nixVersions,
}:
runCommand "sync-exts-versions" { } ''
  mkdir -p $out/bin
  substitute ${../tools/sync-exts-versions.sh.in} $out/bin/sync-exts-versions \
    --subst-var-by 'YQ' '${yq}/bin/yq' \
    --subst-var-by 'JQ' '${jq}/bin/jq' \
    --subst-var-by 'NIX_EDITOR' '${nix-editor.packages.nix-editor}/bin/nix-editor' \
    --subst-var-by 'NIXPREFETCHURL' '${nixVersions.nix_2_20}/bin/nix-prefetch-url' \
    --subst-var-by 'NIX' '${nixVersions.nix_2_20}/bin/nix'
  chmod +x $out/bin/sync-exts-versions
''
