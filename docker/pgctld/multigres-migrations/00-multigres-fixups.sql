-- Multigres Docker init fixups — equivalents of Ansible after-create hooks.
-- Runs as supabase_admin (the migrations role) after all standard migrations.

-- init-scripts run as postgres, so pgcrypto and uuid-ossp extowners are postgres.
-- Standard supabase expected output has supabase_admin as extowner.
UPDATE pg_extension SET extowner = 'supabase_admin'::regrole WHERE extname IN ('pgcrypto', 'uuid-ossp');
