## [17.6.1.043] - 2025-11-09

### ⚙️ Miscellaneous Tasks

- Bump admin api for service versions (#1900)
## [17.6.1.042] - 2025-11-08

### 🚀 Features

- Support multiple versions of the pg_tle extension (#1756)
## [17.6.1.041] - 2025-11-07

### 🐛 Bug Fixes

- Needs to run on merge not pre merge (#1898)
- Grant execute on pg_reload_conf() to postgres (#1892)
## [17.6.1.040] - 2025-11-06

### 🚀 Features

- Support multiple versions of the pgaudit extension (#1758)
## [17.6.1.039] - 2025-11-06

### 🚀 Features

- Bump auth to v2.182.1 (#1894)

### 🚜 Refactor

- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1881)

### 📚 Documentation

- Small fixes to dbmate docs (#1895)
## [17.6.1.038] - 2025-11-04

### 🚀 Features

- Multiple versions for the vault extension (#1661)

### 🧪 Testing

- Start fail2ban before healthcheck in testinfra (#1888)
## [17.6.1.037] - 2025-11-03

### 🐛 Bug Fixes

- Explicitly set pg fail2ban jail backend to auto (#1886)
## [17.6.1.036] - 2025-10-31

### 🚀 Features

- Enable GitHub merge queues (#1849)

### 🐛 Bug Fixes

- Change trigger to `merge_group` in "Release Migrations - Staging / build (push)" workflow (#1884)
- We won't deploy this newest version of plv8 yet (#1885)

### 🚜 Refactor

- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1869)

### 🧪 Testing

- Newline readme (#1883)
## [17.6.1.035] - 2025-10-30

### 🚀 Features

- Update supautils (#1879)
## [17.6.1.034] - 2025-10-30

### 🚀 Features

- Support multiple versions of the plv8 extension (#1676)
## [17.6.1.033] - 2025-10-29

### ⚙️ Miscellaneous Tasks

- Bump wrappers version 0.5.6 (#1877)
## [17.6.1.032] - 2025-10-28

### 🚀 Features

- Support multiple versions of the pg_hashids extension (#1755)
## [17.6.1.031] - 2025-10-28

### 🚀 Features

- *(Nix-flakes)* Add pgBackRest flake (#1859)

### 🐛 Bug Fixes

- Wrappers 0.5.3 missing (#1872)
- Covering migrations for wrappers across all versions` (#1876)

### 🚜 Refactor

- Improve test harness logging and error handling (#1834)

### ⚙️ Miscellaneous Tasks

- Add our substituter config to flake.nix (#1839)
## [17.6.1.029] - 2025-10-25

### 🚀 Features

- Support multiple versions of the pgroonga extension (#1677)

### 🚜 Refactor

- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1862)
## [17.6.1.028] - 2025-10-24

### 🐛 Bug Fixes

- Bump admin-api with enforce ssl fix (#1857)
- Bump version for new release (#1860)

### 🚜 Refactor

- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1861)
## [17.6.1.027] - 2025-10-23

### 🚀 Features

- Support multiple versions of the pg_repack extension (#1688)

### 🚜 Refactor

- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1852)
- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1856)
## [17.6.1.026] - 2025-10-22

### 🚀 Features

- Support multiple versions of the plpgsql_check extension (#1684)

### 🚜 Refactor

- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1848)

### 📚 Documentation

- How to update new structure (#1851)
- Getting started nix install or config revised (#1853)

### ⚙️ Miscellaneous Tasks

- Bump to release (#1855)
## [17.6.1.025] - 2025-10-21

### 🚀 Features

- *(wrappers)* Support more versions (#1831)

### 🚜 Refactor

- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1833)
## [17.6.1.024] - 2025-10-17

### 🐛 Bug Fixes

- Fine tune protection rules to unblock wal-g functionality (#1846)
## [17.6.1.023] - 2025-10-16

### 🐛 Bug Fixes

- *(nix)* Remove '%' character from Nix trusted-public-keys configuration (#1840)
- Remove git revision from postgres package
- Incorporate v3.0.0 supautils (#1844)
## [17.6.1.022] - 2025-10-14

### ⚙️ Miscellaneous Tasks

- Systemd hardening (#1837)
## [17.6.1.021] - 2025-10-10

### 🚜 Refactor

- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1821)
## [17.6.1.020] - 2025-10-09

### 🐛 Bug Fixes

- *(pgmq)* Replace drop_queue function if exists (#1828)

### 🚜 Refactor

- *(postgresq)* Switch to 'include_dir' and then renames conf files to ensure ordering (#1820)
## [17.6.1.019] - 2025-10-09

### 🚀 Features

- Support multiple versions of the pg_jsonschema extension (#1757)
## [17.6.1.018] - 2025-10-09

### 🚀 Features

- Update supautils confs w/ new tables
- Bump auth to v2.180.0 (#1829)
## [17.6.1.017] - 2025-10-08

### 🚀 Features

- Run pg_regress tests after installing the last version of the extension (#1826)
- *(migrations)* Predefined role grants (#1815)

### 🐛 Bug Fixes

- *(pgmq)* Add missing helper function in migration script (#1825)
## [17.6.1.016] - 2025-10-07

### 🚀 Features

- Run pg_regress during extension tests (#1812)
- Support multiple versions of the pgmq extension (#1668)
## [17.6.1.015] - 2025-10-06

### 🚀 Features

- Support multiple versions of the pgrouting extension (#1687)

### 🚜 Refactor

- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1819)
## [17.6.1.014] - 2025-10-06

### 🚀 Features

- Support multiple versions of the pg-graphql extension (#1761)

### 🐛 Bug Fixes

- Update Dockerfiles for changes to postgis multiversion (#1817)

### 🚜 Refactor

- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1813)
- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1818)
## [17.6.1.013] - 2025-10-03

### 🚀 Features

- Support multiple versions of the postgis extension (#1667)
## [17.6.1.012] - 2025-10-02

### 🚀 Features

- Add retry policy for auth service routes (#1782)

### 🐛 Bug Fixes

- Move tmpdir for SAA to one that always exists (#1799)

### 💼 Other

- Automatically cancel old tests/build on new push (#1808)

### 🚜 Refactor

- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1804)
- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1807)
- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1809)
- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1810)
- *(ansible)* Bring our ansible up to modern ansible-lint standards (#1811)

### 📚 Documentation

- Getting started guide in README (#1805)
- Small adjust (#1806)
## [17.6.1.011] - 2025-09-26

### 🐛 Bug Fixes

- Adjust the qemu vars filename
- Templating of SAA service file

### 🚜 Refactor

- *(ansible)* Bring our ansible up to modern ansible-lint standards
## [17.6.1.009] - 2025-09-25

### 🚀 Features

- Supply a slightly different supabase-admin-agent configuration for qemu artifacts
- Support multiple versions of the http extension (#1664)
## [17.6.1.008] - 2025-09-24

### 🚀 Features

- Multiple versions for the pgsodium extension (#1660)
## [17.6.1.007] - 2025-09-24

### 🚀 Features

- Support multiple versions of the rum extension (#1692)
## [17.6.1.006] - 2025-09-23

### 🚀 Features

- Tighten gotrue.service deps and startup behavior (#1783)
- Multiple versions for the `timescaledb-apache` extension (#1749)

### 🐛 Bug Fixes

- Permissions fix for correct sudoers (#1797)
## [17.6.1.005] - 2025-09-16

### 🚀 Features

- Support multiple versions of the hypopg extension  (#1760)

### 📚 Documentation

- Update readme and tool to generate (#1789)
## [17.6.1.004] - 2025-09-12

### 🚀 Features

- *(systemd)* Configure the systemd pager to make debugging via journalctl easier (#1784)
- Update various git-hosted runners with blacksmith runners (#1785)
- Support multiple versions of the vector extension (#1750)
## [17.6.1.002] - 2025-09-04

### 🐛 Bug Fixes

- Bump pg version for new admin mgr and admin api (#1780)
## [17.6.1.001] - 2025-09-03

### 🚀 Features

- Update minor versions of pg 17 and 15  (#1766)

### 🐛 Bug Fixes

- New admin mgr and admin api for recovery target immediate (#1777)
## [17.5.1.021-orioledb] - 2025-09-02

### 🚀 Features

- Bump auth to v2.179.0 (#1776)

### 🐛 Bug Fixes

- Bump postgres versions for auth v2.179.0 (#1779)
## [17.5.1.020-orioledb] - 2025-08-30

### ⚙️ Miscellaneous Tasks

- Bump PostgREST to v13.0.5 (#1775)
## [17.5.1.019-orioledb] - 2025-08-29

### 🚀 Features

- Multi version pg_net including 0.19.5 (#1744)
- Using ubuntu minimal for qemu

### 🐛 Bug Fixes

- Pin entrypoint file download until we can test changes (#1752)
- Ensure amazon-ec2-utils is installed before 24.04 upgrade (#1759)
- *(ci)* Avoid testinfra failure due to loss of ssh connection (#1764)
- Path to vars.yml for mirror postgrest job (#1771)

### ⚙️ Miscellaneous Tasks

- Bump Wrappers version to 0.5.4 (#1768)
- Adding details on EKS build
## [17.5.1.017-orioledb] - 2025-08-12

### 🚀 Features

- Add supabase_etl_admin user

### 🐛 Bug Fixes

- Ubuntu 24.04 mounts disks when available, can change mountpoints" (#1747)
## [17.5.1.015-orioledb] - 2025-08-08

### 🚀 Features

- Source specific version of packer and build with specific go (#1735)

### 🐛 Bug Fixes

- Accurately determine disk mount for upgrade disk xvdp (#1740)

### ⚙️ Miscellaneous Tasks

- Add failure notifications for v3 build
- Remove nix dependency for simple tools
- Version bump amis for release (#1741)
## [17.5.1.014-orioledb] - 2025-08-06

### 🚀 Features

- Bump auth to v2.178.0 (#1733)
## [17.5.1.013-orioledb] - 2025-08-05

### 🚀 Features

- Support multiple versions of the index_advisor extension (#1671)
## [17.5.1.012-orioledb] - 2025-08-04

### 🚀 Features

- Add script to mount/unmount disks (#1727)

### 🐛 Bug Fixes

- *(ext/wrappers)* Restore backward compatibility files for postgres upgrade

### 🧪 Testing

- Release candidate wrappers fix (#1731)
## [17.5.1.011-orioledb] - 2025-07-29

### 🐛 Bug Fixes

- Add wants, requires and after to supabase-admin-agent systemd unit (#1726)
## [17.5.1.010-orioledb] - 2025-07-28

### ⚙️ Miscellaneous Tasks

- Remove unused packages from qemu build
## [17.5.1.009-orioledb] - 2025-07-25

### 🐛 Bug Fixes

- A few updates slipped by in merge, this PR fixes those (#1719)
## [17.5.1.008-orioledb] - 2025-07-24

### 🚀 Features

- Advance to ubuntu 24.04 (#1416)
## [17.5.1.007-orioledb] - 2025-07-23

### 🐛 Bug Fixes

- Admin-agent timer file is a template (#1717)
## [17.5.1.006-orioledb] - 2025-07-23

### 🐛 Bug Fixes

- Missing whitespace after jinja condition (#1718)
## [17.5.1.005-orioledb] - 2025-07-22

### 🚀 Features

- Supautils grants for auth.mfa_factors

### 🐛 Bug Fixes

- Set default_txn_read_only on supabase_read_only_user
- *(ci)* Supabase-admin-agent naming (#1715)

### 🧪 Testing

- Alter API roles timeout

### ⚙️ Miscellaneous Tasks

- Repack admin-agent to public artifacts bucket (#1710)
## [17.5.1.002-orioledb] - 2025-07-17

### 🚀 Features

- Disable default database collector for postgres_exporter
## [17.5.1.001-orioledb] - 2025-07-17

### 🚀 Features

- Oriole beta12 (#1707)

### ⚙️ Miscellaneous Tasks

- Bump to pg_net 0.19.3
## [17.4.1.057] - 2025-07-16

### ⚙️ Miscellaneous Tasks

- Version bump supabase-admin-agent (#1705)
## [17.4.1.056] - 2025-07-15

### ⚙️ Miscellaneous Tasks

- [**breaking**] Upgrade Vector to latest release (#1689)
## [17.4.1.055] - 2025-07-11

### 🐛 Bug Fixes

- User cachix nix installer with pinned nix version (#1700)

### ⚙️ Miscellaneous Tasks

- Bump to PostgREST v12.2.12 (#1699)
## [17.4.1.054] - 2025-07-10

### 🐛 Bug Fixes

- Hardcode the salt gpg keys path as it never changes (#1697)
- Bump ami (#1698)
## [17.4.1.053] - 2025-07-09

### 🐛 Bug Fixes

- An errant rebase lost these changes that run funs for tests (#1696)
- Grant storage schema to postgres with grant option

### 🧪 Testing

- Postgres storage privs

### ⚙️ Miscellaneous Tasks

- Bump versions
## [17.4.1.052] - 2025-07-08

### 🚀 Features

- Bump auth to v2.177.0 (#1694)
## [17.4.1.051] - 2025-07-08

### 🚀 Features

- Multiple versions for the wrappers extension (#1663)
## [17.4.1.050] - 2025-07-07

### 🐛 Bug Fixes

- Needed a release to rollout fixes that address pgmq issues (#1693)

### 🚜 Refactor

- *(nix)* Split flake.nix using flake-parts (#1681)

### 📚 Documentation

- Update current versions in readme (#1690)
## [17.4.1.049] - 2025-07-03

### 🚀 Features

- Add the supabase admin agent to the ami build (#1679)

### 🧪 Testing

- Tests on various docs pages for supabase docs (#1675)
## [17.4.1.048] - 2025-06-26

### 🐛 Bug Fixes

- Allow postgres to grant storage privs to other roles (#1666)
## [17.0.1.097-orioledb] - 2025-06-25

### 🚀 Features

- Install gandalf, salt-wrapper for infra (#1657)

### 🐛 Bug Fixes

- Gandalf path name
## [17.0.1.095-orioledb] - 2025-06-24

### ⚙️ Miscellaneous Tasks

- No longer build Oriole QEMU artifact
- Disable auth config reloading within qemu artifact
- Strip out unnecessary dependencies from QEMU builds
## [17.4.1.044] - 2025-06-23

### 🚀 Features

- Add an action that handles git checkouts for all workflows (#1644)
- Allow checkout of fork repository on workflow approval (#1643)

### 🐛 Bug Fixes

- Pin version of libpq to 17.x (#1649)

### ⚙️ Miscellaneous Tasks

- Fix nix cache configuration
- Use larger runner for other workflows and wait for the nix workflow to succeed (#1652)
- Fix CI regressions (#1655)
- Fix workflow dependencies (#1659)
- Fix and add a check for the nix devshell (#1656)
## [17.4.1.043] - 2025-06-11

### 🚀 Features

- Auth v2.176.1 (#1636)
## [17.4.1.042] - 2025-06-06

### 🚀 Features

- Bumps auth to v2.175.0 (#1627)
- Bumps auth to v2.175.0 (#1631)

### 🐛 Bug Fixes

- *(pg_upgrade)* Enable alter role queries after upgrade completes (#1630)

### 🚜 Refactor

- Deduplicate host and port
## [17.4.1.040] - 2025-06-04

### 🚀 Features

- Upgrade admin-mgr to v0.25.1 (#1618)
## [17.4.1.039] - 2025-06-04

### 🐛 Bug Fixes

- Vault grants post-upgrade

### ⚙️ Miscellaneous Tasks

- Add cargo pgrx v0.14.3 for nix (#1619)
- Bump supautils to v2.9.4
- Bump versions
## [17.4.1.038] - 2025-05-30

### 🚀 Features

- Release a single version of postgres AMI from any branch (#1613)

### 💼 Other

- Remove self-hosting logic from the `supabase/postgres` image  (#1615)

### ⚙️ Miscellaneous Tasks

- Get and use commit of branch we are trying to build (#1614)
- Build pg17 + pg17-oriole for qemu vm
## [17.4.1.037] - 2025-05-27

### 🚀 Features

- Bump auth to v2.174.0 (#1610)

### 🐛 Bug Fixes

- Sync supabase roles with $POSTGRES_PASSWORD (#1604)
## [17.4.1.036] - 2025-05-21

### 🚀 Features

- Covering ranges for upgrades (#1603)
## [17.4.1.035] - 2025-05-20

### 🐛 Bug Fixes

- Continue to use previous way to read old pg version in upgrade script (#1601)
## [17.4.1.034] - 2025-05-19

### 🚀 Features

- Bump auth to v2.173.0 (#1599)

### 🐛 Bug Fixes

- Update default collation to match hosted platform (#1596)
## [17.4.1.032] - 2025-05-19

### 🐛 Bug Fixes

- Update adminapi systemd unit file to wait for the network (#1595)
- Drop pgbouncer from unit after (#1598)
## [17.4.1.031] - 2025-05-17

### 🚀 Features

- Do not enable pgjwt by default in pg 15 (#1592)
## [17.4.1.030] - 2025-05-15

### 🚀 Features

- If upgrade 17 -> 17  modify upgrade process (#1583)
## [17.4.1.029] - 2025-05-15

### 🐛 Bug Fixes

- Also grant pg_create_subscription & pg_monitor post-upgrade

### 🧪 Testing

- Add z_17_roles.sql

### ⚙️ Miscellaneous Tasks

- Publish to private ECR repo
- Bump wrappers version to v0.5.0 (#1589)
## [17.4.1.028] - 2025-05-05

### 🚀 Features

- Bump auth to v2.172.1 (#1585)
## [17.4.1.027] - 2025-05-02

### 🚀 Features

- Revoke supabase_*_admin from postgres

### 🧪 Testing

- Update snapshots

### ⚙️ Miscellaneous Tasks

- Bump versions
## [17.4.1.026] - 2025-05-02

### 🚀 Features

- *(migrations)* Alter internal evt trig owner
- Bump to supautils v2.9.1

### ⚙️ Miscellaneous Tasks

- Bump pg versions
## [17.4.1.025] - 2025-05-01

### ⚙️ Miscellaneous Tasks

- Update admin api to 0.84.1 (#1579)
## [17.4.1.024] - 2025-05-01

### 🧪 Testing

- Role privileges on auth/storage db objects

### ⚙️ Miscellaneous Tasks

- Bump admin api version for larger instance size support (#1578)
## [17.4.1.023] - 2025-04-30

### ⚙️ Miscellaneous Tasks

- Bump admin api version and sb ami version (#1575)
## [17.4.1.022] - 2025-04-28

### 🚀 Features

- Bump admin-api to 0.82 (#1573)

### 🐛 Bug Fixes

- Increment version numbers for adminapi v0.82 (#1574)
## [17.4.1.021] - 2025-04-25

### 🚀 Features

- Keep pgjwt for all versions, deactivated by default in 17/oriole (#1571)
## [17.4.1.020] - 2025-04-24

### 🐛 Bug Fixes

- Grant Vault privs to service_role (#1539)
## [17.4.1.019] - 2025-04-23

### ⚙️ Miscellaneous Tasks

- Add test for pgbouncer.get_auth (#1567)
## [17.4.1.018] - 2025-04-23

### 🚀 Features

- For schema tests, try to use pg_dump (#1562)
- Keep pgjwt present but deactivated for orioledb only to avoid r… (#1557)

### 🐛 Bug Fixes

- Update pgbouncer.get_auth (INFRA-1530) (#1554)

### 📚 Documentation

- Update docs and some of the scripts that run them (#1560)
- Schema.sql per maj version update (#1555)
## [17.4.1.017] - 2025-04-21

### 🚀 Features

- Upgrade to latest admin-api release (0.79.0)

### 🐛 Bug Fixes

- Update wrappers server options post-upgrade
- Wrappers >=0.4.6 check clause
- Wrappers server options again

### 📚 Documentation

- Update the "new migration create" doc to cover missing steps (#1553)
## [17.4.1.016] - 2025-04-16

### 🚀 Features

- Bump wrappers version to v0.4.6 (#1542)

### 🧪 Testing

- Role privileges on vault objects and indexes

### ⚙️ Miscellaneous Tasks

- Bump gotrue to v2.171.0 (#1548)
## [17.4.1.015] - 2025-04-14

### 🧪 Testing

- Pgmq functions' owner modification

### ⚙️ Miscellaneous Tasks

- Bump adminapi to v0.77.2 (#1538)
## [17.4.1.014] - 2025-04-10

### 🚀 Features

- Limit /etc to readonly (#1451)
## [17.4.1.013] - 2025-04-08

### 🐛 Bug Fixes

- Bump versions to add new fixed adminapi version (#1534)

### ⚙️ Miscellaneous Tasks

- Allow manually releasing migrations on stg
- Additional note on qemu build process
## [17.4.1.012] - 2025-04-06

### ⚙️ Miscellaneous Tasks

- Keep oriole numbering consistent
## [17.4.1.011] - 2025-04-06

### 🐛 Bug Fixes

- Restart always pgbouncer service (#1523)
- Adminapi permissions for auth dir (#1524)
- Permissions for github release (#1527)

### 🧪 Testing

- Roles privileges, memberships, attributes
- Realtime publication
- Extensions schema
- Add event trigger function schema
- Storage and auth migrations

### ⚙️ Miscellaneous Tasks

- Explicit permission and quote user definable input in actions
## [17.4.1.009] - 2025-04-03

### 🚀 Features

- Update oriole to latest release, add testing suffix (#1507)

### 🐛 Bug Fixes

- Skip installing ndisc issue resolver in qemu mode
- Update adminapi service for qemu builds

### 🧪 Testing

- Regress policies on auth tables
- Regression for storage schema
## [17.4.1.007] - 2025-04-02

### 🚀 Features

- Release new adminapi and admin-mgr for physical backup pausing (#1516)

### 🐛 Bug Fixes

- Change qemu build to oriole
- Remove ref to non-existent file

### 🧪 Testing

- Regression for auth schema
## [17.4.1.006] - 2025-04-02

### ⚙️ Miscellaneous Tasks

- No longer ship kong in the qemu artifact
## [17.4.1.005] - 2025-04-01

### 🐛 Bug Fixes

- Change oriole builds to use pg_ctl instead of initdb

### 🧪 Testing

- Output default event triggers

### ⚙️ Miscellaneous Tasks

- Run regress tests before migration tests
- *(qemu)* Ship the initialized data dir at a different location
- All versions need bump for release to succeed
## [17.4.1.004] - 2025-03-31

### 🚀 Features

- Enable runtime configuration reloads for auth (#1229)

### 🐛 Bug Fixes

- Flake check not working locally on linux
- Evtrigs ownership (#1489)

### 🧪 Testing

- Regress default privileges

### ⚙️ Miscellaneous Tasks

- Update codeowners
- Mv ansible migration test to nix flake check
- Remove migration file from client (#1494)
- Introduce tooling for pg 17.4 non-orioledb (#1420)
## [17.0.1.053-orioledb] - 2025-03-25

### ⚙️ Miscellaneous Tasks

- Set pg_graphql to stable rust (#1476)
## [17.0.1.052-orioledb] - 2025-03-24

### 🚀 Features

- Enable pg_buffercache
- Build pg17-oriole qemu artifacts

### ⚙️ Miscellaneous Tasks

- Add PG team as codeowners on the repo (#1483)
- Update README.md
- Bump adminapi_release to `0.76.0` (#1491)
## [17.0.1.050-orioledb] - 2025-03-19

### 🚀 Features

- Reland vault w/o pgsodium (#1452)
## [17.0.1.049-orioledb] - 2025-03-18

### 🚀 Features

- Wal-g v 3 (#1456)

### 🐛 Bug Fixes

- Protect plpgsql

### ⚙️ Miscellaneous Tasks

- Update README with nix run .#update-readme (#1481)
## [17.0.1.048-orioledb] - 2025-03-17

### ⚙️ Miscellaneous Tasks

- Add cleanup for qemu bootstrap (#1479)
- Create a programmatic listing of the commands that can be run (#1480)
- Bump pg 17 oriole (#1482)
## [17.0.1.047-orioledb] - 2025-03-14

### ⚙️ Miscellaneous Tasks

- Bump wrappers version to v0.4.5 (#1460)
## [17.0.1.046-orioledb] - 2025-03-13

### ⚙️ Miscellaneous Tasks

- Update adminapi release (#1478)
## [17.0.1.045-orioledb] - 2025-03-13

### ⚙️ Miscellaneous Tasks

- Bump gotrue to v2.170.0 (#1477)
## [17.0.1.044-orioledb] - 2025-03-13

### 🚀 Features

- Bundle virtiofsd as part of the k8s artifact

### 🐛 Bug Fixes

- Pgbouncer ownership (#1474)
## [17.0.1.043-orioledb] - 2025-03-12

### ⚙️ Miscellaneous Tasks

- Rm xmrig src by setting attribute to throw (#1473)
## [17.0.1.042-orioledb] - 2025-03-06

### ⚙️ Miscellaneous Tasks

- Deprecate pg_backtrace (#1468)
## [17.0.1.041-orioledb] - 2025-03-01

### 🚀 Features

- Remove api key checks in envoy (#1465)

### ⚙️ Miscellaneous Tasks

- Try to fix frequent timeout on install of ansible-galaxy (#1466)
## [17.0.1.040-orioledb] - 2025-02-27

### 🚀 Features

- Add test for security definer functions (#1461)
- No longer ship an initialized pgdata dir as part of QEMU artifact (#1463)

### 🐛 Bug Fixes

- Correctly select root disk partition (#1244)
## [17.0.1.039-orioledb] - 2025-02-21

### 🐛 Bug Fixes

- Update migration to support vault 0.2.8 and above

### ⚙️ Miscellaneous Tasks

- Bump pg_graphql version (#1455)
## [17.0.1.038-orioledb] - 2025-02-21

### 🚀 Features

- Ensure that nfs clients are available on the QEMU artifact

### 🐛 Bug Fixes

- Pg_net event trigger (#1457)
## [17.0.1.037-orioledb] - 2025-02-20

### 🐛 Bug Fixes

- Remove pg_net grants

### 📚 Documentation

- We will now generate readme from data (#1453)
## [17.0.1.036-orioledb] - 2025-02-18

### 🐛 Bug Fixes

- Revert migrations
- Pgsodium mask_role migration

### ⚙️ Miscellaneous Tasks

- Restore flake-url arg (#1450)
## [17.0.1.035-orioledb] - 2025-02-12

### 🚀 Features

- Vault sans pgsodium

### 🐛 Bug Fixes

- Nix flake check
- A better cleanup process
- Gh actions oom try without overmind

### ⚙️ Miscellaneous Tasks

- Create a workflow_dispatch only method with input, for docker … (#1440)
- This substitution no longer needed
- Need schema files in proper place for tests
- Try with flake url to target current changes
- More attempts at graceful shutdown
- More attempts to handle shutdown across arch
- Revert to earlier
- More tweaks to run in gh actions
- Already in background
- This line may be causing segfault
- Do nothing if not running
- Too many trap exits
- Mod stop_postgres for daemon
- Adjust cleanup
- Allow other scripts to stop the start-server cluster
- Also deactivate supabase_vault in test (#1439)
## [15.8.1.038] - 2025-02-09

### ⚙️ Miscellaneous Tasks

- Increase files limit for Postgres (#1429)
- A new release version to cover ulimit -n change for postgres (#1438)
## [17.0.1.033-orioledb] - 2025-02-07

### 🚀 Features

- Build and publish a QEMU image artifact (#1430)
## [17.0.1.032-orioledb] - 2025-02-06

### 🚀 Features

- Allow all auto_explain parameters to be user customizable
- Log ddl by default

### ⚙️ Miscellaneous Tasks

- Bump supabase-admin-api version to 0.74.0 (#1425)
- Remove unused/deprecated code
- Update ci.yml to reflect where data is now stored
- Wip upgrade pgroonga to latest (#1418)
- Bump to v4 to fix deprecation failure
- Only gitignore schema.sql
## [17.0.1.030-orioledb] - 2025-02-01

### ⚙️ Miscellaneous Tasks

- Bump adminmgr to 0.24.1 (#1424)
## [17.0.1.029-orioledb] - 2025-01-30

### 🐛 Bug Fixes

- Custom scripts were not configured to run correctly (#1422)
- Bump gotrue version to v2.169.0 (#1423)
## [17.0.1.022-orioledb] - 2025-01-29

### 🚀 Features

- Add `supautils.drop_trigger_grants`

### 🐛 Bug Fixes

- Publish pg_upgrade scripts on vars.yml updates (#1414)

### ⚙️ Miscellaneous Tasks

- Fixing tool used to run dbmate migration checks (#1419)
- Reduce keepalive time to 30m, interval to 60s (#1421)
## [17.0.1.020-orioledb] - 2025-01-20

### 🐛 Bug Fixes

- Salt install in all-in-one image
- Update pgsodium extension scripts (#1397)

### ⚙️ Miscellaneous Tasks

- Remove legacy ENV syntax
- Remove publish_to_fly step for aio image
## [17.0.1.019-orioledb] - 2025-01-15

### 🚀 Features

- Update oriole extension to beta9 (#1407)
## [17.0.1.017-orioledb] - 2025-01-13

### 🚀 Features

- Add new supautils.privileged_role_allowed_configs
- Update envoy lds with origin protection keys (#1403)
## [17.0.1.016-orioledb] - 2025-01-10

### ⚙️ Miscellaneous Tasks

- Build ami (#1406)
## [17.0.1.014-orioledb] - 2025-01-08

### ⚙️ Miscellaneous Tasks

- Bump wrappers to v0.4.4 (#1396)
## [17.0.1.013-orioledb] - 2025-01-07

### 🐛 Bug Fixes

- Trigger docker image build on changes to ansible vars
- Bump gotrue version to v2.168.0 (#1400)
## [17.0.1.012-orioledb] - 2025-01-02

### 🐛 Bug Fixes

- Add extensions schema to postgis topology search path (#1392)
## [17.0.1.011-orioledb] - 2024-12-24

### 🐛 Bug Fixes

- Upgrade script workflow (#1375)
- Upgrade ami to contain auth 2.167.0 (#1389)
## [17.0.1.010-orioledb] - 2024-12-17

### 🐛 Bug Fixes

- Jump update auth version to 2.165.1 from 2.163.2 (#1383)
## [17.0.1.009-orioledb] - 2024-12-16

### 🚀 Features

- Explicit create /var/lib/postgresql (#1376)

### 🐛 Bug Fixes

- Pgmq perms+data (#1374)
## [17.0.1.008-orioledb] - 2024-12-12

### 🚀 Features

- Bootstrap tool for local infra set up on macos only (#1331)

### ⚙️ Miscellaneous Tasks

- Name oriole ami with conventions used through the rest of supabase systems (#1354)
- Update pgpsql-http version closes #1348 (#1353)
- Add building and cache for debug and src (#1361)
- Use all_fdws flag for buildFeatures attribute (#1359)
- Let testinfra try to connect again if ssh conn is lost (#1355)
- Merge 15.6 changes into develop (#1368)
## [16.3.1.021] - 2024-12-02

### ⚙️ Miscellaneous Tasks

- Bump oriole to beta8 (#1349)
- Bump other AMI versions (#1350)
## [15.8.1.014] - 2024-11-29

### 🚀 Features

- Add an env var we can detect in various utilities for managing oriole machines (#1344)

### ⚙️ Miscellaneous Tasks

- We do not use the --migrate down so removing that statement (#1341)
- Build and release oriole beta7 (#1345)
- Bump release (#1346)
## [16.3.1.019] - 2024-11-26

### ⚙️ Miscellaneous Tasks

- Bump releases (#1339)
## [16.3.1.011] - 2024-11-25

### 🐛 Bug Fixes

- Publish action, wrappers package issue, test of 15.8 image upgrade (#1324)

### ⚙️ Miscellaneous Tasks

- Bump pg_jsonschema version to support pg 17
## [16.3.1.018] - 2024-11-20

### 🚀 Features

- Separate envoy lds configs for self-hosting and supabase use-cases (#1325)

### 🐛 Bug Fixes

- Just a small typo in file name (#1330)

### ⚙️ Miscellaneous Tasks

- Merge `release/15.6` changes into `develop` (#1320)
## [16.3.1.013] - 2024-11-07

### ⚙️ Miscellaneous Tasks

- Adding support for x86_64-darwin (#1310)
## [16.3.1.012] - 2024-11-06

### 🚀 Features

- Packaging and devshell with various cargo-pgrx versions! (#1277)
- Tmp disable pg_net on macos and allow for server start on macos (#1289)
- Update envoy lds file to strip `sb-opk` header (#1297)

### 🐛 Bug Fixes

- Clickhouse deps needs git on path to install and/or build (#1300)
- Needs git in buildInputs too (#1301)

### ⚙️ Miscellaneous Tasks

- Bump wrappers to v0.4.3 (#1286)
## [16.3.1.010] - 2024-10-17

### 🚀 Features

- Pg-restore utility (#1243)

### 🐛 Bug Fixes

- Reformat ec2 cleanup commands (#1267)
- Disable pg_stat_monitor (#1261)
- Only consider pgsodium to be valid if they are in these versions (#1276)

### ⚙️ Miscellaneous Tasks

- Cut releases for 15.8 and 16.3 (#1279)
## [15.8.1.003] - 2024-10-04

### 🐛 Bug Fixes

- *(develop)* Account for pg_stat_monitor major version upgrade (#1249)
- *(pg_upgrade)* Retry commands within the cleanup step; wait until PG is ready to accept connections (#1251)
- *(upgrades)* Collision when patching wrappers lib locations for upgrades (#1253)
- Add .well-known endpoints to envoy config (#1255)
## [15.8.1.002] - 2024-10-02

### 🚀 Features

- Make sure to source debug and src from our build (#1246)

### 🐛 Bug Fixes

- Only grant pg_read_all_data if it exists (#1242)

### ⚙️ Miscellaneous Tasks

- Updates to run physical backups as a service (#1235)
## [15.8.1.001] - 2024-09-28

### 🚀 Features

- Package gdal + fix basePackages to switch pg version correctly (#1231)
- Bump gotrue version to v2.162.0 (#1241)

### 🐛 Bug Fixes

- Account for `public` grantee
- *(ci)* Respect postgresVersion input (#1237)
- AIO - update platform defaults position on postgresql.conf to ensure overrides happen successfully (#1238)

### ⚙️ Miscellaneous Tasks

- Add pgrest v12.2 metrics endpoint as adminapi upstream source on AIO (#1233)
## [15.6.1.124] - 2024-09-24

### 🚀 Features

- Update pgaudit to handle pg versions 15 and 16 (#1228)
- Bump auth to v2.161.0

### ⚙️ Miscellaneous Tasks

- Bump aio image version, 15.1.1.90 on DockerHub is a tad broken and outdated, e.g. it has the removed pg_backtrace
## [15.6.1.122] - 2024-09-19

### 🚀 Features

- Bringing postgres package into our package set (#1195)
- *(pg_upgrade)* Use self-hosted nix installer if available; move files out of /tmp (#1191)

### 🐛 Bug Fixes

- Statement_timeout=0 during bootstrap user switch migration (#1196)
- Run timescaledb_pre/post_restore() (#1197)
- Continue running migrations when auth.uid/auth.role/auth.email are missing in the database (#1187)
- Disable client connections during upgrade (#1199)
- Pg_shadow issue
- Alter role set escaping (#1204)
- *(pg_upgrade)* Add nix cache for self-hosted installs (#1205)
- *(pg_upgrade)* Bump bootstrap user switch timeout to 10m
- Standardize how supabase-groonga is installed on machine (#1212)
- Double-escaped identifiers
- Schema name escaping
- Exclude partitioned indexes when swapping owners (#1216)
- Disable pgsodium event trigger when swapping roles

### ⚙️ Miscellaneous Tasks

- *(pg_upgrade)* Tweak timeout of bootstrap user switch script (#1198)
- Create an isolated output for postgres, to expose debug symbols (#1200)
- Consolidate to just one start-client for postgres tooling (#1194)
- Bump wrappers to v0.4.2 (#1181)
- Set precedence to use ipv4 resolution in gettaddrinfo
- Version bump
## [15.6.1.121] - 2024-09-11

### 🐛 Bug Fixes

- Correct reference to Envoy Lua filters
## [15.6.1.120] - 2024-09-11

### 🚀 Features

- Change bootstrap user to `supabase_admin` upon upgrade (#1125)
## [15.6.1.119] - 2024-09-11

### 🚀 Features

- Configure Envoy to compress additional response types

### 🐛 Bug Fixes

- Run nix-gc before pg_upgrade (#1189)
## [15.6.1.118] - 2024-09-08

### 🐛 Bug Fixes

- Update Envoy config to have circuit breaker settings, retries, increased timeouts and remove empty key query params
- Remove pg_backtrace from shared_preload_libraries

### 📚 Documentation

- Flesh out the process for updating a package. (#1186)
## [15.6.1.117] - 2024-09-05

### 🐛 Bug Fixes

- Add HOME env var to supervisord managed postgres (#1182)

### ⚙️ Miscellaneous Tasks

- Introduce a darwin builder just for the nix build (#1180)
- Bump adminapi version (#1185)
## [15.6.1.116] - 2024-09-02

### 🚀 Features

- Bump auth to v2.160.0 (#1179)

### 🐛 Bug Fixes

- Wrappers nix-based pg_upgrade
- Nix replica command
- Make sure that ec2 is cleaned up in all cases of flow end
- Only keep 1mil pg_cron job run details during pg_upgrade (#1174)

### 📚 Documentation

- Updating for packaging and package updating (#1157)

### ⚙️ Miscellaneous Tasks

- Shellcheck fix
- More fix
- Disable salt-minion for first boot
- Remove old workflows that are no longer used
- Consolidate `release/15.6-lw12` into `develop` (#1142)
- Bail on executing grow_fs is resize2fs is already running
## [15.6.1.109] - 2024-08-11

### 🐛 Bug Fixes

- It is required to run this at the end of AMI build (#1109)
## [15.6.1.106] - 2024-08-08

### 🚀 Features

- Make pg_regress available in /bin outputs
- Add our updated fork of pg_backtrace (#1098)

### ⚙️ Miscellaneous Tasks

- Getting the tests to run, and to print a file location
## [15.6.1.104] - 2024-08-05

### 🐛 Bug Fixes

- Update auth to v2.158.1 (#1086)
## [15.6.1.102] - 2024-08-02

### 🚀 Features

- Docker base psql15.6 img and release (#1072)
- Allow postgres to run on darwin
- Plv8 and flake check for aarch64 darwin
- Randomize ami name on testinfra for 15.6 (#1080)

### ⚙️ Miscellaneous Tasks

- Bump gotrue version to v2.157.1
- Remove docker code
- Remove pg_prove wrapping
- No need to build docker here
- Fail flake check if pg_isready fails
## [15.6.1.100] - 2024-07-29

### 🚀 Features

- Enable ipv6 support
- Upgrade adminapi to latest release
- *(migrations)* Alter lo_export/lo_import owner
- Bump gotrue version to v2.139.2 (#882)
- Bump auth version to v2.140.0 (#883)
- Bump auth to v2.142.0 (#884)
- Bump auth version to v2.143.0
- Use envoy-hot-restarter.py and start-envoy.sh in all-in-one image
- Enable pgstattuple and pg_prewarm
- Bump auth to v2.143.1 (#897)
- Bump auth to v2.144.0
- Bump supautils to v2.1.0
- Pg_cron 1.6.2
- Auth upgrade version to v2.145.0 (#922)
- Bump adminapi to v0.63.2
- Dblink extension custom script
- Bump wrappers to v0.3.0 (#923)
- Supautils v2.2.0 (#935)
- Bump auth version to v2.147.0 (#940)
- Bump version (#941)
- Postgis built in our bundle again and matching version we need (#954)
- Bump auth to v2.151.0 (#962)
- Plan_filter configs (#972)
- Systemd timer unit to restart network on NDisc failure (#971)
- Upgrade auth version to v2.152.0
- Set admin-api to 0.64.1 and bump AMI version to 15.1.1.56 (#980)
- Update `supautils.policy_grants`
- Add auth base env file
- Add auth optimizations service
- Delegated-init support for Fly projects (#997)
- Automate pg_upgrade testing (#695)
- Bump auth to v2.154.2 (#1011)
- Grant predefined roles to postgres
- Add safeupdate to shared_preload_libraries
- Bump auth version 2.155 (#1024)
- Bump auth version to v2.155.1 (#1032)
- Bump auth to v2.155.3 (#1043)
- Install salt-minion on AMI (#1041)
- New flake app runs migrations before starting (#1056)
- Allow overriding pg_upgrade scripts publish target version (#1066)

### 🐛 Bug Fixes

- Docker builders
- Allow dual dstack operation for adminapi (#865)
- Enable public ip for build instance
- Install packer plugins
- Cleanup multiple instances
- Public ip for testinfra
- Libssl-dev dependency chain breaking across architectures (#877)
- Remove pgbouncer test from ami tests (#879)
- Ensure Vector retains perms to write to a file under the pg log dir
- Edit Envoy config on startup to support case where IPv6 is disabled
- Gracefully shutdown Kong on service stop
- Ensure that Kong service is stopped before Envoy service is started
- Check if port 80 or 443 is already in use before starting Envoy
- Pg_net grants post pg-upgrade (#905)
- Fly postgres exporter service definition
- Remove auth stats collection from postgres_exporter
- Release 15.1.1.30 (#918)
- Fix typo - missing space on dockerhub-release-aio.yml (#919)
- Specify mode for adminapi sudoers
- *(docker-aio)* Bring PostgREST and Kong subprocesses under supervisorctl management (#929)
- Avoid libsodium.org to address build flakiness
- Enable generated pg optimizations on the AIO image
- Remove spurious newline
- Make workflow resilient to spurious newlines
- Gotrue config persistence for AIO (#961)
- Retry a few more times for disk to become available (#974)
- Add route checking to network fix script (#975)
- Disable Kong info headers
- Fix invalid keys in systemd service
- Release adminapi 0.64.2 (#988)
- Kong deb url moved away
- Salt amd64 install (#1000)
- Add default startretries value to services provisioned in AIO image; bump admin-mgr to 0.20.0 (#1005)
- Bump auth version (#1006)
- Include custom overrides config in AIO (#1014)
- Restore group perms to PG dir post-upgrade (#1017)
- AIO SSL enforcement
- Exclude `pgbouncer`, `supabase_admin` and `supabase_storage_admin` queries from user queries
- Stop pg_net worker during pg_upgrade (#1030)
- When we dl supautils in oriole Dockerfile, we use tar archive instead of deb (#1034)
- Supautils was missing checksum step after download (#1033)
- Disable safeupdate during pg_upgrade (#1038)
- Ensure that we pull apt updates before building
- Fixes build on aarch64-darwin
- Fixes build on aarch64-darwin
- Build wrappers on aarch64-darwin
- Remove `safeupdate` from `shared_preload_libraries` (#1049)
- Ensure that the last extension does not get dropped during upgrades (#1050)
- Account for trailing commas (#1061)
- Wrappers upgrade from 0.3.0 to 0.4.1 (#1062)
- Flake check was broken/could not start postgres (#1063)

### ⚙️ Miscellaneous Tasks

- Include the supabase release on disk
- Indicate breaking change requirement
- Run envoy config update scripts
- Enable s3 dualstack
- Update the release version
- Update postgrest testinfra config
- Upgrade adminapi to latest build
- Remove dblink (#854)
- Bump pg_tle version to 1.3.2 (#819)
- Bump adminapi to v0.62.0 (#860)
- Reorder exts
- Dbmate annotations
- Bump version
- Tweak autoshutdown script (#859)
- Upgrade adminapi to latest build
- Add ipv6 support for pg egress collection
- Bump AMI version
- Update adminapi to v0.62.3
- Bump adminapi v0.62.4
- Fix libssl dep (#875)
- Add newline (#878)
- Bump pg_graphql to v1.5.0 (#880)
- Upgrade to latest internal artifacts
- Patch plv8 (#888)
- Clean up comment that's no longer relevant
- Remove pgbouncer from docker aio image (#907)
- Bump base AIO image for testinfra
- Upgrade admin-api to latest release
- Allow manual workflows for Release Docker AIO image (#915)
- Patch pg_cron perms post-pg_upgrade (#858)
- Gh action AIO release with manual input for base docker image (#916)
- Docker aio - add pitr.log collection to vector (#917)
- Bump adminmgr to 0.15.1 (#926)
- Upgrade admin-mgr
- Upgrade adminapi to v0.63.3
- Bump auth version to v2.146.0 (#932)
- Drop nixConfig from the flake, we config on install now (#944)
- Bump admin-api to 0.63.5
- Don't persist supautils.conf across upgrades (#946)
- Add backend team as an additional codeowner on orioledb
- Run logrotate every 5 mins
- Bump gotrue version to 2.149.0 (#956)
- Bump gotrue version to v2.150.0 (#957)
- Allow manually triggering package-plv8 action
- Disable kong reporting (#965)
- Add metric for pending WAL files to be archived (#970)
- Bump adminapi to 0.64.0 (#969)
- AMI release for NDisc network fix (#973)
- Bump PostgREST to devel release (#977)
- Temporarily hardcode PostgREST version for aio image (#978)
- Add PG prestart script (#984)
- Cut new release
- Bump gotrue version to v2.153.0 (#992)
- Bump version
- Bump admin-mgr to 0.19.2 (#1001)
- Aio - move delegated-init to /data dir (#1002)
- More defensive handling of pg_egress_collect symlink in AIO (#1004)
- Bump postgrest to v12.2.0
- Upgrade to latest admin-mgr
- Update queries for docker image
- Move static ext configs to base template
- Fix AIO SSL; bump admin-mgr (#1031)
- Bump PG version (#1035)
- Generate pg_upgrade logs on successful run as well (#1039)
- Bump Wrappers version to 0.4.1 (#1029)
- Remove placeholder file before root resize
- Release bump (#1054)
- Enable all extensions during pg_upgrade testing (#1051)
- More pg_upgrade script nix-centric fixes (#1059)
- Add the rest of the FDWs to nix-built wrappers
- Additional handling on post-upgrade generated sql execution
- Mirror postgrest image on version bump (#1053)
- Bump nix ami version
- Update version string to be compliant with prod naming
- Bump version to trigger release (#1071)
- Bump gotrue version to v2.156.0 (#1073)
- Allow for a larger number of connections
- Update envoy config and trigger build
## [15.1.0.155] - 2024-01-08

### 🚀 Features

- Bump gotrue version to v2.132.3 (#853)

### ⚙️ Miscellaneous Tasks

- Fix AIO signal handling; propagate exit signal to all child process
- Bump adminmgr
- Cleanup
## [15.1.0.154] - 2023-12-23

### ⚙️ Miscellaneous Tasks

- Bump postgrest to v12.0.2
## [15.1.0.153] - 2023-12-19

### ⚙️ Miscellaneous Tasks

- Update adminmgr, fix gotrue, fix config perms (#847)
- Upgrade Admin API to 0.59.0
## [15.1.0.152] - 2023-12-18

### 🚀 Features

- Bump auth version in postgres to v2.130 (#846)

### ⚙️ Miscellaneous Tasks

- Bump postgrest to v12.0.1 (#844)
- Update AIO image todo (#845)
- Fly refactoring; fixes; extra LSN shipping coverage (#800)
## [15.1.0.151] - 2023-12-14

### 🚀 Features

- Add `systemctl try-restart` commands to adminapi sudoers
- Add `supervisorctl status` commands and other commands for `services:envoy` to adminapi sudoers
- Upgrade Admin API to 0.58.0

### 🐛 Bug Fixes

- Use C collation for compiling extensions with orioledb
- Bump pgrx version for wrappers build (#843)
- Set `autorestart` to `true` for Envoy supervisord conf
## [15.1.0.150] - 2023-12-13

### ⚙️ Miscellaneous Tasks

- Add postgres team as codeowner or version file
- Bump wrappers version to 0.2.0
## [15.1.0.149] - 2023-12-11

### 🚜 Refactor

- Use stdout access logger instead of file access logger using /dev/stdout

### ⚡ Performance

- *(envoy)* Only log when status code >=400

### ⚙️ Miscellaneous Tasks

- Remove plv8 from exclusions (#813)
- Bump postgrest to v12.0.0
## [15.1.0.148] - 2023-12-09

### 🐛 Bug Fixes

- Rebuild orioledb base image (#836)
## [15.1.0.147] - 2023-12-08

### ⚙️ Miscellaneous Tasks

- Deploy AIO Postgres image to Fly.io's registry (#835)
- Enable the en_US.UTF-8 locale (#834)
## [15.1.0.146] - 2023-12-08

### 🚀 Features

- Upgrade Admin API on all-in-one image to 0.57.1

### 🐛 Bug Fixes

- /etc/envoy permissions
- Exit Envoy config script if not enabled
- Make tar and chown follow symlinks for /etc/envoy
## [15.1.0.144] - 2023-12-07

### 🚀 Features

- Update orioledb base image and s3 config script (#818)
## [15.1.0.143] - 2023-12-07

### 🐛 Bug Fixes

- Set explicit group and permissions for Envoy-related files
## [15.1.0.142] - 2023-12-07

### 🐛 Bug Fixes

- Remove unnecessary comment

### ⚙️ Miscellaneous Tasks

- Upgrade to Admin API v0.57.1
- Bump `postgres-version`
## [15.1.0.141] - 2023-12-07

### 🚀 Features

- Add Envoy proxy support
- Bump gotrue version (#826)

### 🐛 Bug Fixes

- Update Kong release URL, old one will be retired sometime
- Use rbac instead of lua filter for basic auth
- Replace ports in Envoy config correctly
- Don't use TLS for Admin API in Envoy config
- Add grant for Envoy to adminapi sudoers conf
- Add `set -eou pipefail` and redirect stderr to stdout
- Set `pipefail` and redirect stderr to stdout in Supervisor Envoy config

### 📚 Documentation

- Add warning comment to update `gateway-28` in Kong release URL
- Add comment explaining why `apikey` query parameter needs to be removed

### 🧪 Testing

- Add tests for `apikey` removal

### ⚙️ Miscellaneous Tasks

- Bump `postgres-version`
- Check that version includes non-numeric characters for manual AMI builds
- Re-bump `postgres-version` since it's used by an existing AMI
## [15.1.0.138] - 2023-12-06

### 🚀 Features

- Add `/etc/gotrue.overrides.env` to gotrue systemd unit

### 🐛 Bug Fixes

- CI checks

### ⚙️ Miscellaneous Tasks

- Upgrade to newest adminapi
## [15.1.0.137] - 2023-12-04

### 🚀 Features

- Bump gotrue to v2.125.1 (#820)

### 🐛 Bug Fixes

- Change orioledb base image to s3 branch (#808)

### ⚙️ Miscellaneous Tasks

- Ubuntu18 fixes for postgis & plv8
- Use ubuntu:bionic as base layer instead of ppa
- Remove ubuntu 18 support
- Add a CI check for the release version
- Update gha test-infra timeout to 60min
- Set lock_timeout to authentictor role (#814)
## [15.1.0.136] - 2023-11-30

### ⚙️ Miscellaneous Tasks

- Bump version (#809)
## [15.1.0.135] - 2023-11-28

### 🚀 Features

- Remove restriction on setting content-type response header (#807)

### ⚙️ Miscellaneous Tasks

- Exclude check_role_membership during pg_upgrade (#806)
## [15.1.0.134] - 2023-11-27

### 🚀 Features

- Build extensions using orioledb as base
- Add github action workflow

### 🐛 Bug Fixes

- Patch rum to compile for orioledb
- Patch timescaledb to compile for orioledb
- Patch pgvector to compile using clang
- Build supautils from source
- Patch upstream entrypoint script
- Avoid using incorrect logger
- Use stable rust toolchain
- Adjust pg_graphql.deb paths so that the extension loads
- Adjust pg_jsonschema.deb paths so that the extension loads
- Drop obsolete pg_graphql function signature

### ⚙️ Miscellaneous Tasks

- Retry stopping PG if it initially fails (#789)
- Stop postgresql restart during upgrades (#790)
- Remove non-develop branches from orioledb ci
- Restart gotrue and postgrest after pg_upgrade (#791)
- Configure aws creds before running tests
- Temporarily disable ami building
- Attach tags to target instances
- Add additional tags
- Timeout and logging
- Reenable disabled code
- Bump wrappers version to 0.1.19 (#793)
- Bump adminapi and admin-mgr binaries (#792)
- Compile pg_graphql from source for OrioleDb Dockerfile
- Compile pg_jsonschema from source for OrioleDb Dockerfile
- Add some network debugging tools, clean out unused pkgs (#794)
- Add postgres team as owners on orioledb files
- Ensure fail2ban stays disabled when FAIL2BAN_DISABLED is set  (#796)
- Fix flaky AMI test
- Ignore exit code of cleanup step
- Increase timeout
- Compile wrappers from source for OrioleDb Dockerfile (#797)
- *(testinfra)* Check for connectivity
- Wait a few seconds before an additional psql stop during upgrades (#805)
- Update docker aio entrypoint to handle GOTRUE_DISABLED (#803)
## [15.1.0.133] - 2023-11-08

### 🚀 Features

- Bump gotrue to v2.109.0 (#786)

### ⚙️ Miscellaneous Tasks

- Bump postgrest to v11.2.2
## [15.1.0.132] - 2023-11-02

### 🐛 Bug Fixes

- Wrappers workaround if files are the same (#776)
- Pg_cron perms

### ⚙️ Miscellaneous Tasks

- Fixing wrappers workaround once again (#777)
## [15.1.0.131] - 2023-10-26

### ⚙️ Miscellaneous Tasks

- Fix wrappers' lib name (#774)
- Remove postgres role perms post-upgrade (#775)
## [15.1.0.130] - 2023-10-25

### 🐛 Bug Fixes

- Readd missing step to ubuntu 18 binary collection workflow (#770)
- Directly copy file instead of streaming to stdin (#771)

### ⚙️ Miscellaneous Tasks

- *(testinfra)* Scaffold ami tests
- *(testinfra)* Initial ami test
- Bump wrappers version to 0.1.18
- Include vim-tiny in image
- Temporarily disable AMI tests
- Fix ubuntu 18 lib collection order (#772)
- Bump pg_graphql to v1.4.2
- Pg_upgrade md5-to-scram migration (#769)
## [15.1.0.129] - 2023-10-19

### 🐛 Bug Fixes

- Migrations release workflow permissions
- Allow postgres role to allow granting usage on graphql and graphql_public schemas (#761)
- Rollback postgrest to 11.2.0 (#766)
## [15.1.0.128] - 2023-10-18

### 🚀 Features

- Bump gotrue to v2.104.2

### 🐛 Bug Fixes

- Readme images location (#762)
## [15.1.0.127] - 2023-10-17

### 🚀 Features

- Bump gotrue to v2.104.0

### 💼 Other

- Adding sysctl params for rebooting the OS after oomkiller kills a process (#759)
## [15.1.0.126] - 2023-10-16

### 🚀 Features

- Bump gotrue to v2.103.0 (#755)

### 🐛 Bug Fixes

- Grant authenticator to supabase_storage_admin

### ⚙️ Miscellaneous Tasks

- Use saved GPG key for Postgres' PPA; update pg_upgrade version detection regexp (#749)
## [15.1.0.124] - 2023-10-05

### 🐛 Bug Fixes

- Add per image scope to gha cache (#745)

### ⚙️ Miscellaneous Tasks

- Bump postgrest to v11.2.1
- Bump admin-api to 0.51.0
## [15.1.0.122] - 2023-10-03

### 🚀 Features

- Bump gotrue version (#744)
## [15.1.0.121] - 2023-09-27

### 🐛 Bug Fixes

- Increase the start timeout to 1 day
- Fix typo in manifest playbook admin-mgr url

### ⚙️ Miscellaneous Tasks

- Ubuntu 18 build fixes (#733)
- *(aio)* Add simple testinfra test for postgrest
- *(testinfra)* More postgrest tests & add a TODO
- Upgrade admin-mgr and upload artifact to internal bucket
- Preserve md5 auth scheme if project used it before the upgrade
- Ubuntu 18 binaries
- Attempt different gpg keyserver
- Cleanup
- More gpg madness
- Bump adminapi (#741)
## [15.1.0.118] - 2023-09-11

### ⚙️ Miscellaneous Tasks

- Upgrade to latest adminapi build
## [15.1.0.117] - 2023-09-05

### 🐛 Bug Fixes

- Use aws profiles for publishing migrations
- Inform PG after log rotation
## [15.1.0.116] - 2023-08-30

### 🚀 Features

- Bump pgvector to v0.5.0

### 🐛 Bug Fixes

- Increase restart interval for systemd-resolved
## [15.1.0.115] - 2023-08-29

### 🚀 Features

- Bump supautils to 1.9.0
## [15.1.0.114] - 2023-08-21

### 🚀 Features

- Bump supautils to v1.8.0

### ⚙️ Miscellaneous Tasks

- Fix for sar making sure directory is available before service starts
- Update configure-aws-credential action to resolve deprecation warning
- Update postgres-version
- Clarify before-create script
## [15.1.0.113] - 2023-08-17

### 🚀 Features

- Bump gotrue to v2.92.1 (#721)

### ⚙️ Miscellaneous Tasks

- Bump postgrest to v11.2.0
## [15.1.0.112] - 2023-08-14

### 🚀 Features

- Bump gotrue to v2.92.0 (#719)
## [15.1.0.111] - 2023-08-10

### 🐛 Bug Fixes

- Ensure default PG logrotate config is removed (#718)

### ⚙️ Miscellaneous Tasks

- Push lsn checkpoint on autoshutdown; enable use of recovery_target_lsn; bump admin-mgr (#714)
- Bump Wrappers version to 0.1.16 (#716)
## [15.1.0.109] - 2023-08-03

### 🚀 Features

- Bump gotrue v2.91.0 (#715)
## [15.1.0.108] - 2023-08-02

### ⚙️ Miscellaneous Tasks

- Remove pg_switch_wal (#713)
- Bump Wrappers version to 0.1.15 (#711)
- Bump admin API and admin-mgr (#710)
## [15.1.0.106] - 2023-07-28

### 🚀 Features

- Bump image version (pgsodium 3.1.8)

### 🐛 Bug Fixes

- Ensure that the test slot gets dropped

### ⚙️ Miscellaneous Tasks

- Preserve binaries across reboots (#708)
- Fix symlink location; access mode; docker image mirroring (#712)
## [15.1.0.105] - 2023-07-19

### 🐛 Bug Fixes

- Set lc_collate to c.utf-8 explicitly (#696)

### ⚙️ Miscellaneous Tasks

- Set hot_standby to off by default (#700)
## [15.1.0.103] - 2023-07-11

### 🚀 Features

- Enable DDL audit logging by default

### ⚙️ Miscellaneous Tasks

- Bump gotrue version to v2.82.4 (#694)
## [15.1.0.101] - 2023-07-06

### ⚙️ Miscellaneous Tasks

- Remove pgBouncer pg_hba rules
- Relocate pg_egress_collect file
- Bump gotrue & postgres version (#691)
## [15.1.0.100] - 2023-07-05

### 🚀 Features

- Logrotate postgres logs
- Publish postgres 0.14.2
- Set up PgBouncer
- Add queries for additional metrics (#59)
- Install jq as part of base image
- Boot time optimizations
- Add queries for additional metrics (#59)
- Disable additional unnecessary services
- Install admin-api on supabase builds
- Ship osquery as part of AMI
- Pgbouncer optimization
- Upgrade supautils
- Add support to allow expanding multiple volumes
- Add separate EBS data volume at AMI build time (#244)
- Adds script to help toggle readonly mode; adds adminapi monitoring service
- Add `track_io_timing` to `supautils.privileged_role_allowed_configs`
- Basic support for nftables
- Bump gotrue to v2.33.3 (#407)
- Add database upgrade scripts (#250)
- Bump gotrue to v2.36.1 (#417)
- Bump supautils to v1.7.0
- Bump gotrue to v2.40.0 (#453)
- Bump gotrue v2.40.1 (#464)
- Enable protobuf support for PostGIS (#480)
- Add pg_egress_collect service (#486)
- Bump gotrue to v2.47.0 (#537)
- Upgrade adminapi to latest release (#549)
- Bump gotrue to v2.51.4
- Upload software artifacts to internal bucket
- Add supautils to docker image
- Bump gotrue to v2.57.2 (#609)
- Remove `disable.vault` suffix from 15.1.0.66 (#610)
- *(extensions)* Upgrade pg_tle to v1.0.3
- Release 15.1.0.68
- Bump gotrue to v2.60.1 (#615)
- Bump gotrue (#623)
- Add walg to postgres image
- Enable sysstat collection
- Upgrade to pgbouncer 1.19.0
- Build AIO image
- Bump gotrue to v2.66.0 (#640)
- Bump gotrue to v2.70.0 (#662)
- Bump gotrue v2.74.2 (#675)

### 🐛 Bug Fixes

- Adds arm64 regions
- Fail2ban configuration
- Aws af-south-1 is x86, not arm
- Wrong link to pl/java
- Reverse blocking of AWS instance metadata
- /etc/postgresql should be owned by postgres
- Symbolic linking for Postgres binaries
- Adding dependencies for timescaledb
- Ensure pgbouncer works upon systemctl start
- Correct check for load and store exclusives
- Add in wal-g dependencies
- Put stat_extensions.sql back in
- Clean up duplicate variables
- Update log rotation location and frequency (#62)
- Pg_stat_statements column names changed in PG13
- Man-db is a cronjob and not a systemd service (#66)
- Logrotate on u20 uses systemd timers
- Create the /var/log/postgresql directory towards the end of the build
- Disable cron access (#103)
- Allow adminapi to restart postgresql service
- Fail2ban config to watch ssh failures
- Ddos preferences for sshd bans
- Only require PG optimizations on internal builds
- Shuffle tasks around
- Postgres bin directory location for pgsodium extension when running a docker build (#147)
- Execute sql files after PG startup (#166)
- Let docker use the right arch (#167)
- Disk resizing script updated for new disk layout
- Update supautils.privileged_extensions
- Commence_walg_restore.sh script (#224)
- Update vector version to 0.22.3
- Resize data volume
- Edit node_exporter collection exclusion rules to include /data as a monitored mount path
- Clean up docker build
- Allow keygen script to create the pgsodium root key on docker
- Retain key packages for PostgREST and Kong (#281)
- Disallow configuring pgaudit to log parameters
- Keep auditd log directory
- Installs and removes pg_prove as needed for AMI assertions
- Keep auditd log directory
- Only impose a timeout on PG stop operations
- Add gotrue and postgrest profiles (#314)
- Allow vector write access to postgresql log (#313)
- Add missing entry to gotrue profile (#321)
- Ensure fail2ban, postgresql, auditd disabled during first boot
- Provide unit name when disabling fail2ban (#326)
- Reduce ansible playbook build time (#340)
- Use json override
- Bump gotrue to v2.23.2 (#354)
- Allow postgis file path access and validate extensions. (#350)
- Disable migration tasks (#358)
- Temporarily disable extension check and pgroonga build (#360)
- Add pgtap file for extension testing (#356)
- LibSFCGAL.so permission for apparmor and disable pgroonga (#372)
- Skip wrappers from extension install tests (#377)
- Use correct key for CI run (#380)
- Update aa-pg-profile for pljava
- Allow known non-ssl entries on pg_hba.conf (#388)
- Use correct variable in extension tasks (#398)
- Remove async block for jsonschema
- Update aa-pg-profile for gotrue
- Don't hold default-jre-headless version during docker build (#404)
- Re-enable pgroonga extension (#412)
- Update vector profile for logs (#416)
- Update migration
- Grant pgsodium functions to service_role (#443)
- Pgsodium extension custom script (#454)
- Docker build process (#469)
- Switch to aws roles for releases
- Source download for pg_repack (#500)
- Fix arch type for admin-mgr
- Add missing migration files to build test
- Add runtime dependency to pg_net package
- Checkinstall version must start with digit
- Wal2json package version
- Ccache workflow git context
- Cache mount invalidation
- Plv8 workflow reference
- Postgres_fdw: alter fdw owner to `postgres`
- Add unit tests for table privilege
- User permissions for extension schemas (#560)
- Add libgdal runtime dependency
- *(docker)* Missing ca-certificates
- Var interpolation in sfcgal download
- Workaround for tle bug (#622)
- Only run if workflow completes on develop (#624)
- Add pg_tle in shared_preload_libraries prior to running migrations (#625)
- Download and configure walg for arm64
- Handle inconsistent aarch64 binary name
- Increase postgres start timeout
- Build postgis from source
- Fail2ban regex for pgbouncer (#647)
- Only symlink when pgdata_real is defined
- Update build and runtime dependencies for groonga
- Make pgdata real optional
- Remove quotes from build args
- Corrects typo that prevented wal-g being enabled (#639)
- Perms and dir structure for physical backups (#650)
- Pgbouncer config perms (#673)
- Correct permissions on functions upon restore (#678)
- Pgbouncer config persistence after reboot (#684)
- Insert pgbouncer pg_hba entries before any other rules (#686)

### 💼 Other

- Delete unnecessary files
- Add pgAudit
- Update README.md to include pgAudit.
- Add Sydney and London as covered regions
- Add South Africa as covered region
- Connection pooling
- Disable DB auto-discovery (#85)
- Use correct indentation for 'when' conditional statement
- Update postgrest checksum (#137)
- Build arm64 AMI image
- Donot remove llvm-11-dev package and update postgres-version (#191)
- Set llvm package as manual to prevent autoremoval
- Add missing package for fail2ban
- Move config to custom .conf
- Add authenticator to reserved_memberships
- Add apparmor profile for postgresql, pgbouncer, vector
- Listen on ipv4 address
- Add async_mode flag to support docker builds
- Remove grants to pg_graphql tables that no longer exist AO v0.5.0 (#347)
- Add more rules to aa vector/gotrue profile (#406)
- Allow read perm for vector (#424)
- Adjust postgresql oom_score (#438)
- Update perm for /opt/gotrue path
- Update aa-profile postgres (#465)

### 📚 Documentation

- Adds enterprise sponsors

### 🧪 Testing

- Add basic postgres database image test using pgTAP
- Update basic unit test sql (#300)

### ⚙️ Miscellaneous Tasks

- Add tagging to future AMI builds
- Running default prettier on all files
- Add pgcron to supabase/postgres docker
- Add pg_cron to shared_preload_libraries
- Allow image name to be editable from CLI
- #30 Setting docker default to UTF-8
- #29 Add pg-safeupdate
- Reorganise default ami_regions for aws
- Adding additional security updates for DO
- Update marketplace scripts and dependencies
- Bump to 0.15.0
- Remove dependency on ANXS postgres
- Adding ap-northeast-1 to AWS ARM regions
- Changing to Ubuntu 20.04 & r6g instance for ARM build
- Update log_filename value in postgresql.conf
- Completely remove dependency from anxs postgres
- Build PgBouncer from source instead
- Split setup-misc into its components
- Regression - put back installation of EC2 instance connect
- Adding postgrest
- Update playbook.yml to reflect split of setup-misc
- Add timescaledb (Apache2 version) as an extension
- Add test script for postgres installation
- Clean up and consolidate configuration for PgBouncer
- Boyscout separate versions of aws cli depending on architecture
- Boyscout remove extra steps from postgrest
- #3 setupfail2ban filter against PG brute force logins
- Remove ansible role anxs/postgres
- Ensure that postgres user has access to ssl certs
- Create extension internally instead
- #49 install supautils extension
- #50 enable postgis_sfcgal extension
- #45 additional extension - PgRouting
- #58 settings to reduce memory overcommit
- Disable pgbouncer as well
- Disable motd service as well
- Install a few utilities
- Append logfiles for systemd services
- Add apne2 region as a target
- Switch back to supabase_admin for metrics collection
- Remove build dependencies
- Install ansible-pull
- Remove queries
- Install pg_plan_filter extension
- Install pg_net extension
- Set max_slot_wal_keep_size to 1024 mb (#102)
- Upgrade adminapi version
- Upgrade adminapi and wal-g
- Configure journald for persistent storage
- Additional perms for adminapi
- Set default command
- Run logrotation every ten minutes
- Upgrade AdminAPI (#130)
- Remove now unused env file reference (#136)
- Update adminapi to v0.16.1
- Enable debug symbols on PG compile (#151)
- Install pg_graphql extension (#152)
- Upgrade adminapi (fastboot)
- Preserve timestamps for shell history
- Remove .DS_Store
- Update docker image
- Aggressive configuration for ssh fail2ban
- Bump docker version (#220)
- Set /etc/hosts file
- Remove osquery (#222)
- Update wal2json version in readme to commit 53b548a
- Update custom walg conf (#225)
- Revert pg_stat_monitor_changes
- Use stdout logging for docker container
- Ensure Vector gets restarted
- Upgrade adminapi to pick up fail2ban management
- Restart PG on service failure (#260)
- Use a readonly script for pgsodium keys on AMI
- Upgrade to 0.26.0 admin-api
- Release docker image
- Update pgsodium root key path to be managed
- Create pgsodium extension
- Grant pgsodium perms to postgres user
- Update postgres-version to 14.1.0.59
- Cleanup CI file naming
- Bump release to include vault extension
- Disable logging all statements by default
- Trigger docker build (#285)
- Drop v prefix from docker tag
- Add init scripts to docker
- Update services (#289)
- Add workflow to mirror image
- Remove node_exporter
- Add additional permissions to adminapi (#296)
- Bump gotrue version to 2.16.7 (#298)
- Remove libpq-dev from PG deps
- Cleans up unix socket auth for PG conns
- Update docker image to v71
- Remove separate service
- Add perms to manage pgbouncer lifecycle
- Upgrade adminapi release
- Updated readonly mode management script
- Updated readonly mode postgresql script subcommand name
- Remove readonly mode subcommand output formatting
- Readonly mode management script update
- Bump adminapi version
- Bump postgres version
- Build arm docker image
- Adds codeowners file
- Merge multi-arch manifests
- Split command into multiple lines for readability
- Use local context
- Bump postgres version (#317)
- Bump gotrue version to 2.17.5
- Bump gotrue version (#324)
- Add migrations script to postgres AMI (#329)
- Update postgres ami version (#332)
- Bump GoTrue to v2.19.4(bug fix) (#334)
- Copy init scripts in dockerfile
- Migrate with dbmate on ci
- Validate schema file on ci
- Run migrations when initialising docker
- Fix migration test
- Build latest image in test workflow
- Configure postgres version via env var
- Run tests from migration (#339)
- Set authenticator timeout (#342)
- Publish ami build to docker hub
- Test docker image build on demand
- Parse raw version string
- Selectively enable pr build
- Fix test build error
- Disable async when building from docker
- Flip arg order
- Release new staging image
- Move query to its own migration file (#346)
- Bump docker image to v83-rc0 (#349)
- Add cli team as migrations codeowners (#351)
- Bump gotrue version to v2.25.1 (#355)
- Upgrade adminapi to 0.27.1
- Rollback pgsodium to 3.0.4 (#362)
- Revoke supabase_admin from authenticator (#359)
- Add Migration scripts along with extensions test (#365)
- Update postgres (migration) ami version to 14.1.0.90 (#368)
- Bump gotrue version to v2.30.4 (#373)
- Bump version to 14.1.0.92 (#375)
- Add eu-west-3 to list of regions (#371)
- Upgrade to adminapi 0.27.2
- Switch to using internally hosted adminapi artifacts (#382)
- Update pgbouncer and admin-api perm for ssl-config (#370)
- Download adminapi archives locally instead of on target (#383)
- Adds GoTrue exporter firewall rule (#385)
- Use adminapi from public artifacts bucket
- Use internal ansible module to fetch adminapi artifact (#390)
- Bump adminapi version (#391)
- Remove ansible adminapi artifact copy step (#392)
- Upgrade postgrest to v10
- Create user supabase_replication_admin
- Add as a reserved role
- Upgrade adminapi build
- Remove extension functions from DB
- Use platform directly
- Mirror built image to ghcr (#401)
- Fix pg15 docker builds (#414)
- Fix failing unit test (#418)
- Fix failing unit test (#419)
- Update wal-g; update README.md (#421)
- Bump version (#422)
- Copy extension files for Docker builds (#425)
- Update to pgsodium and vault. (#430)
- Pg15 - Adds docker support for pgx extensions (#428)
- *(ci)* Fix migrate test
- *(ci)* Use amacneil/dbmate:main
- *(ci)* Update schema dump
- Bump pgsodium 3.1.2 (#433)
- Update vault (#434)
- Update vault 0.2.7 (#435)
- Revert pgsodium to 3.1.1 (#436)
- Update pgsodium 3.1.4 to fix bs compat with old dumps from <= 3.0.4 (#441)
- Update adminapi version to 0.31.1 (#442)
- Build AMIs on manual dispatch
- Slack notifications on failures
- Use bind mount for buildcache instead of copy step (#439)
- Add pg_upgrade_files (#459)
- Add swapfile
- Update-timescaledb (#473)
- Cleanup extension sources before proceeding to next task (#474)
- Remove killall command (#467)
- Add pgroonga MeCab tokenizer support (#462)
- General db upgrade improvements; pgsodium compatibility (#460)
- Disable RemoveIPC to avoid shared memory issues (#488)
- Update adminapi.sudoers.conf
- Update adminapi.sudoers.cofn
- Allow custom config on /etc/postgresql
- Bump adminapi
- Bump pg version (#494)
- Fix typo in filename (#499)
- Fix typo in pg_repack task (#501)
- Add pkg-config to setup-postgres.yml (#502)
- Add pkg-config to setup-postgres.yml (#503)
- Download pg_repack source; rename pgvector extension name in supautils (#504)
- Bump pg version (#507)
- Update migrations to reflect pg_net 0.7 schema requirements (#510)
- Init admin-mgr (#514)
- Terminate builder instance on job cancellation (#512)
- Grant auth roles to postgres user
- By default, allow pgbouncer SSL connections (#517)
- Create tags and GH releases when we build an AMI
- Tag the correct commit when creating a release
- Update pg upgrade scripts (#485)
- Upgrade postgrest to v10.1.2 (#523)
- Test release process (#524)
- Always rebuild container in tests
- Improve build cache with multistage docker (#528)
- Share ansible vars with docker build (#529)
- Fix plv8 version reference
- Enable ccache for plv8 ami build (#535)
- Add libsodium to package requires
- Remove support for pljava
- Cache large build artifacts
- Package plv8 separately
- Rename postgres major variable
- Parse dockerfile for build image tag
- Fix plv8 merge manifests job
- Add plv8 source to build cache
- Update upgrade scripts (#533)
- Create pgsodium directory in docker
- Create extensions stage from scratch
- Add tests for creating extensions
- Run tests as superuser
- Create all extensions before running db tests
- Update schemas list test
- Run build tests on both arm64 and x86
- Fix build args
- Refactor image tag for plv8 job
- Add workflow to rebuild ccache
- Post-upgrade - disable jit; maintain md5 encryption if previously enabled (#541)
- Switch postgis and pgroonga to source builds
- Move dockerfile to root context
- Remove docker playbook
- Update test workflow
- Bump version to rc
- Add missing workflow call
- Update test user to fix ami release
- Bump rc version
- Rollback extensions from pgtap tests
- Bump release version
- Test privileges of cron schema
- Test privileges of net schema
- Enable vault test
- Wrap pgtle in transaction
- Wrap pgtap in transaction
- Remove unused compose file
- Pin dbmate version
- Bump release version
- Simplify extension testing (#553)
- Bump admin-mgr to v0.3.1 (#562)
- Temporarily disable Vault (#566)
- Release 15.1.0.51
- Bump release version
- Also upload software manifest and archives to prod s3
- Grant pg monitor role to postgres
- Update migration file order
- Remove unused statements
- Combine apt commands for fewer layers
- Enable clang optimizations on Postgres (#584)
- Trigger build
- Bump gotrue version to v2.54 (#586)
- Only attempt to build AMI if version is updated
- Upgrade admin-api to latest release
- Bump to 15.1.0.59
- Grant auth roles to supabase_storage_admin user (#590)
- Trigger build
- Upgrade adminapi
- Adminapi upgrade
- Use internal mirror for sfcgal archive
- Bump admin api to 0.40.0 (#602)
- Create upgrade archives without leading /tmp dir
- Enable Vault (#598)
- Enable Vault with safety measures (#611)
- Upgrade scripts - only update libpq reference if major version older than current (#606)
- Build Ubuntu 18 binaries (#614)
- Fix typo (#621)
- Bump Wrappers version to 0.1.10
- Upgrade to postgrest v10.2.0
- Fix race conditions when running a pg upgrade (#629)
- Bump postgres version (#630)
- Upgrade to postgrest v11.0.1
- Bump docker release version
- Upgrade pg_tle
- Send pg exporter logs to journald
- Log upgrade failures remotely to project (#635)
- Fix walg installation
- Bump Wrappers version to 0.1.11 (#642)
- Use ubuntu focal as base docker image (#644)
- Bump image version
- Temporarily revert pgrst to 10.2 (#646)
- Disable pgbouncer logfile output (#648)
- Disable arm64 build
- Point workflow to proper Dockerfile
- Fix version interpolation
- Add AIO Dockerfile to workflow
- Revert pg_cron 1.4.2 (#652)
- Update release version
- Add rapidjson and tokenizer dependencies
- Bump release version
- Standardize gotrue release version
- Remove unnecessary config
- Install docker built extensions on AMI (#539)
- Fly fixes; PITR + logging + shutdown + perms (#665)
- Fix variable name during fly init (#666)
- Make autoshutdown toggleable; disable shutdown by default (#670)
- Enable swap on fly (#671)
- Update adminapi; persist scripts for AIO image (#676)
- Bump postgrest to v11.1.0
- Bump Wrappers version to 0.1.14
- Fix AIO image gotrue config file persistence (#680)
- Fix binary collection; install .deb pg binaries for u18 (#681)
- Add pg_egress_collect support to AIO image
- Untar pgbouncer userlist for AIO image (#685)
- Add pg_upgrade scripts publishing workflow; renamed scripts (#683)
- Provision pg_upgrade_scripts folder (#688)
