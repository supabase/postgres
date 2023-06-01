# Guidelines for upgrading or adding new extensions

One of the common worklow breakages caused by new extensions, or upgraded extensions, is failures in logical restores. A few workflows to verify when making changes to extensions are essentially various combinations straddling the change:

- [ ] backup/restore on a vanilla project
- [ ] backup/restore on a vanilla project (single-file)
- [ ] backup/restore on a project with the extension enabled
- [ ] backup/restore on a project, after the extension has been enabled and then disabled
- [ ] backup from an old project (w/o change), restore to a new project (w/ change)
- [ ] backup from older project (e.g. early 13/14/15 build), restore to a new project (w/ change)

Unless otherwise mentioned, backups refer to the "multi-file" backup style used for our hosted platform.
