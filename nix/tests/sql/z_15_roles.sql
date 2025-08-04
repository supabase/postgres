-- version-specific role memberships
select
    r.rolname as member,
    g.rolname as "member_of (can become)",
    m.admin_option
from
    pg_roles r
join
    pg_auth_members m on r.oid = m.member
left join
    pg_roles g on m.roleid = g.oid
order by
    r.rolname, g.rolname;
