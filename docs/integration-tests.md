# Integration Tests

## Workflow

<img width="2804" height="1354" alt="CleanShot 2026-11-23 at 10 47 54 AM@2x" src="https://github.com/user-attachments/assets/a963738a-9ed7-4a9b-841a-dcf68badd4bd" />

Currently, integration tests are useful as a reviewer tool and are non blocking.  They will become blocking in future.

## Starting a test

### External Contributors

To kick off an integration test on a public Pull Request (PR), a `supabase/postgres` repo committer or admin adds a comment to the PR:

```
/integration-test <FULL-SHA>
```

The `FULL-SHA` _must_ be the full git SHA for the current PR branch `HEAD`.  For reasons why, see [Security][#Security].

### Committers

Committers will have their PRs run the integration tests automatically.  The decision on this is in progress.

## Security

For details on security for running integration tests on un-trusted public PRs, see the [Public to Private Workflow Dispatch RFC](https://app.notion.com/p/supabase/Public-to-Private-Repo-Workflow-Dispatch-4145004b775f8002b05bea63a5c6c0ca?source=copy_link).

Add no details beyond the RFC link to this section.
