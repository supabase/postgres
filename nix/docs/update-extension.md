
# Update an existing nix extension


1. Create a branch off of `develop`
2. For instance, if we were updating https://github.com/supabase/postgres/blob/develop/nix/ext/supautils.nix we would:
   1. change the `version = "2.2.1";` to whatever our git tag release version is that we want to update to
   2. temporarily empty the `hash = "sha256-wSUEG0at00TPAoHv6+NMzuUE8mfW6fnHH0MNxvBdUiE=";` to `hash = "";` and save `supautils.nix` and `git add  .`
   3. run `nix build .#psql_15/exts/supautils` or the name of the extension to update, nix will print the calculated sha256 value that you can add back the the `hash` variable, save the file again, and re-run nix build .#psql_15/exts/supautils.
   4. NOTE: This step is only necessary for `buildPgrxExtension` packages, which includes supabase-wrappers, pg_jsonschema, and pg_graphql. Otherwise you can skip this step. For our packages that are build with `buildPgrxExtension` you will need to prepend the previous version to the `previousVersions` variable before updating the version in the package (for instance if you are updating `supabase-wrappers` extension from `0.4.1` to `0.4.2` then you would prepend `0.4.1` to this line https://github.com/supabase/postgres/blob/develop/nix/ext/wrappers/default.nix#L18 ). 
   5. Add any needed migrations into the `supabase/postgres` migrations directory
   6. update the version in `ansible/vars.yml` as usual
   7. You can then run the `nix flake check -L` tests locally to verify that the update of the package succeeded. 
   8. Now it's ready for PR review.
   9. Once the PR is approved, if you want the change to go out in a release, update the common-nix.vars.yml file with the new version prior to merging.
  

