
# Update an existing nix extension


1. Create a branch off of `develop`
2. For instance, if we were updating https://github.com/supabase/postgres/blob/develop/nix/ext/supautils.nix we would:
   1. change the `version = "2.2.1";` to whatever our git tag release version is that we want to update to
   2. temporarily empty the `hash = "sha256-wSUEG0at00TPAoHv6+NMzuUE8mfW6fnHH0MNxvBdUiE=";` to `hash = "";` and save `supautils.nix` and `git add  .`
   3. run `nix build .#psql_15/exts/supautils` or the name of the extension to update, nix will print the calculated sha256 value that you can add back the the `hash` variable, save the file again, and re-run nix build .#psql_15/exts/supautils. 
   4. Add any needed migrations into the `supabase/postgres` migrations directory
   5. You can then run tests locally to verify that the update of the package succeeded. 
   6. Now it's ready for PR review.
  

