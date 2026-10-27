# Security Policy

Thank you for helping keep Supabase Postgres and its users safe.

## Reporting a vulnerability

Please report suspected vulnerabilities through our HackerOne program:
<https://hackerone.com/supabase>. Please do not open public GitHub issues or
pull requests for security problems.

This repository contains Supabase Postgres: the Postgres build that Supabase
runs, the extensions bundled with it, and the roles, grants, functions and
configuration that set up a new database. The same images run every project
database on the hosted Supabase platform and are used by people who self-host
Supabase. We accept reports for both, and we triage them differently (see
"Hosted vs. self-hosted" below).

## How database privileges work here

Most reports about this repository are about privilege escalation inside the
database, so two facts frame them.

- **On the hosted platform, customers do not get superuser.** Your project's
  `postgres` role is the most powerful role you hold, but it is not a
  superuser. Superuser is reserved for Supabase's own administrative role,
  `supabase_admin`. Gaining superuser from a customer role is a valid
  finding.
- **Superuser is not the end of the road.** What you can do with it, such as
  reaching the host, another project or Supabase's own credentials, decides how
  the finding is rated.

## What we consider a vulnerability

In general, we want to hear about anything that lets a lower-privileged
database role act with more privilege than it was granted: reaching
superuser or a role Supabase reserves for itself from a customer role on the
hosted platform, reaching superuser from a non-superuser role on a default
self-hosted install, escaping from the database to the host, or reaching
another project. The problem should be present in the current image on the
hosted platform or in a default self-hosted setup.

Examples of what this includes (these are illustrations, not a complete list):

- **Unsafe privileged functions.** A `SECURITY DEFINER` function owned by a
  privileged role that has no pinned `search_path`, that builds SQL from caller
  input with `EXECUTE` or `format()` without quoting it, or that a lower role
  can call when it should not be able to.
- **Privileged code that runs your objects.** A background worker or other
  privileged process that writes to a table a lower role can attach triggers
  to, or otherwise runs code that a lower role controls, in a privileged
  context.
- **The extension install path.** A way for a customer role to install an
  extension, or an extension version, that hands it privileges it should not
  have, or to get attacker-controlled extension code run with privileged
  rights.
- **Overly broad grants.** Bootstrap, migration or extension setup scripts
  that grant a lower role more than it needs, when that grant leads to
  escalation.
- **Escaping the database.** Turning superuser into code execution on the host,
  access as root, or access to privileged cloud credentials.
- **Cross-tenant access.** Reaching another project's database, data or
  secrets from your own project.

## What we do not consider a vulnerability

Reports that rely on the behavior below will normally be closed as
informative or not applicable.

**By design**

- **Superuser on a self-hosted install.** On self-hosted Supabase the default
  administrative access to the database is already superuser. Findings that
  start with that access, or with root on the host, and end at the same
  privilege do not cross a security boundary.
- **Non-superuser roles can install allowed extensions.** On the hosted
  platform this is how customers install extensions without superuser. It
  applies to any role in the database, and is not limited to `postgres`. A
  role being able to install an allowed extension is not by itself an
  escalation. Show what the role gains that it should not have.
- **Extension functions that roles are meant to use.** For example, the
  `pg_net` functions can be executed by database roles, because features
  depend on them. They live in a schema that the Data API does not expose.
- **Your own SQL.** Functions, RPCs, grants and policies that you write are
  your responsibility. A `SECURITY DEFINER` function you created, an RPC that
  exposes an extension function to `anon`, or SQL injection in your own
  function is a bug in your project, not in this repository.

**Prerequisites that make the attack pointless**

- The attacker needs a privileged database role, such as `postgres`, and the
  result is something that role can already do: reading or changing the
  project's data, reading credentials stored in the database, or making
  outbound network requests through an extension.
- The attacker needs `anon` or `authenticated` to run DDL, such as `CREATE
  TRIGGER`, or to open a direct database session. The Data API does not
  provide a way to run DDL, and those roles cannot log in. Such a chain needs
  a separate flaw. Show that flaw.
- The attacker needs root or `sudo` on the host, needs to modify the image, or
  needs superuser to first change the functions, grants or extension versions
  that Supabase ships.

**Reports that are not evidence of a flaw**

- **Source reading without a working escalation.** Show the escalation on a
  real database you own, with the role you started as and the role you ended
  as.
- **Claims of code execution without proof.** If you claim impact beyond
  superuser, show it. Writing a file is not the same as running code.
- **A flaw that has already been fixed.** Check the latest image and the
  public commit history. Hosted projects receive fixes after they reach the
  image.
- **Unreviewed AI output** that bundles many findings, none of which crosses a
  boundary.

## Out of scope for every Supabase asset

These are excluded program-wide (see also
<https://supabase.com/.well-known/security.txt>). They are repeated here so
you do not need to leave this repository to find them.

- Clickjacking on pages with no sensitive actions.
- Unauthenticated, logout and login CSRF.
- Attacks requiring MITM or physical access to a user's device.
- Attacks requiring social engineering.
- Any activity that could lead to the disruption of our service (DoS).
  This means volumetric attacks, load testing and flooding. A vulnerability in
  our code that lets an unprivileged attacker crash a service or exhaust
  resources for other users or tenants is in scope. Denial of service that only
  affects the attacker's own project, or that needs admin or owner privileges,
  is not.
- Content spoofing and text injection issues without showing an attack vector,
  or without being able to modify HTML/CSS.
- Email spoofing.
- Missing DNSSEC, CAA or CSP headers.
- Lack of Secure or HttpOnly flags on non-sensitive cookies.
- Dead links.
- User enumeration.

## Known and documented behavior

Please check these before reporting.

- **Extensions are installed into the `extensions` schema by default** on the
  hosted platform, so that their functions are not exposed through the Data
  API. The Security Advisor warns when an extension has been installed into
  the `public` schema.
- **The `postgres` role is not a superuser** on hosted projects. Superuser is
  reserved for Supabase.

## Hosted vs. self-hosted

On the hosted platform, the boundary is between the roles a customer holds
(`postgres` and the roles it creates, plus `anon`, `authenticated` and
`service_role`) and superuser. On a self-hosted install, the operator already
has superuser, so the boundary is between the non-superuser roles in the
shipped image and superuser. We accept self-hosted findings when the shipped
image and the documented setup lead to the problem, starting from a
non-superuser role. Label your report as described in the next section.

Some findings depend on how the hosted platform configures the database, for
example which extensions a customer role may install. Say whether you also
tested a standalone install, because that decides who else is affected.

## How to write a report that gets triaged quickly

- **Say what you tested, at the top of the report and in the title.** Use one of
  these labels, for example `[Production] ...` in the title and a "Target" line
  at the start of the description:
  - **Production**: the hosted Supabase platform, against a project you own.
    Include the project ref and the role you connected as. Never test another
    customer's project.
  - **Self-hosted, default configuration**: the image from this repository,
    or the self-hosted Supabase setup, run exactly as shipped or as our
    self-hosting guide describes, with no changed settings. Include the image
    tag and how you started it.
  - **Self-hosted, custom configuration**: you changed settings, grants or
    extension versions, or built a modified image. List every change and why.
    We triage these lower unless the setting is one we recommend or document.

  Reports that do not say which of the three they are about are slower to
  triage, and are often closed with a request to retest. A finding that works
  only on a custom configuration is not a finding against production.

- **Test a real database.** Code reading alone is rarely enough. Static
  analysis findings need a working proof of concept against one of the targets
  above.
- **Give a short, runnable PoC.** The exact SQL, run as the role you name, and
  output showing the result, for example `select current_user,
  usesuper from pg_user where usename = current_user` before and after.
  Include cleanup steps.
- **State the attacker's starting position.** Which role do they connect as,
  and how did they get it (the dashboard SQL editor, a database password, the
  Data API with an anon key)? Reports that start from a role that already has
  the privilege they describe are our most common reason to close.
- **Name the boundary you crossed.** Which role, host or project could you
  not reach before? If nothing was crossed, it is probably a hardening
  suggestion.
- **Do not go further than you need to.** Once you have shown superuser,
  stop and report. Do not try to go further against the platform's
  infrastructure without contacting security@supabase.com first.
- **Check the docs, this file and recent commits first.** If the behavior is
  documented, or fixed in the latest image, explain why it still fails.
- **Include versions.** The Postgres version, the image tag, and the versions
  of the extensions involved.
- **One issue per report.** Link variants of the same root cause instead of
  filing each variant separately. If you chain several issues, say which step
  is new.
- **Do not send unreviewed AI output.** Reports that were not reproduced by a
  human and that ignore the documentation are closed. AI-assisted analysis is
  fine when you have verified the result.
- **Respond to follow-up questions.** Reports that go quiet after we ask for a
  reproduction are closed.

## Severity

We rate severity by realistic impact. Reaching superuser from a customer role
on the hosted platform is valid, but is usually rated lower than its raw
description suggests, because the rating follows what it leads to.
Escaping to the host as root, reaching privileged cloud credentials, or
reaching another project is rated higher. Issues that need an existing
privilege or a non-default configuration are rated lower even when they are
valid, and we may fix them as defense in depth.

## Testing and disclosure

These are our program-wide rules. They also apply to AI agents and automated
tools acting on your behalf.

**Testing**

- Do not run automated scanners against other customers' projects. Scanners can
  run up costs for our users, can disrupt services, and our own security
  systems cannot tell hostile reconnaissance from research. If you want to run
  an automated scanner, notify security@supabase.com first and run it only on
  your own Supabase project.
- Do not attack projects that belong to other customers.
- Do not take advantage of a vulnerability you find, for example by downloading
  more data than necessary to demonstrate it, or by deleting or modifying other
  people's data.

**Disclosure**

- Do not reveal the problem to others until we have researched and fixed it and
  informed affected customers.
- If you want to share your research publicly (a conference, a blog or any
  other public forum), send us a draft for review and approval at least 30 days
  before the publication date. Do not include data about Supabase customer
  projects, customers' data, or information about Supabase employees,
  contractors or partners.

**What we promise**

- We will respond to your report within 5 business days with our evaluation and
  an expected resolution date.
- If you have followed these instructions, we will not take legal action against
  you in regard to the report.
- We will handle your report with strict confidentiality and will not pass on
  your personal details to third parties without your permission.
- We will keep you informed of our progress.
- In public information about the problem, we will name you as the discoverer
  unless you prefer otherwise.
