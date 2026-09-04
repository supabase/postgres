-- CVE-2026-2005: heap buffer overflow in pgcrypto's pgp_*_decrypt_bytea() on an
-- oversized PGP session-key length. The fix hardens the PGP packet-length parser
-- shared by the symmetric and public-key bytea decrypt paths.
--
-- Upstream commits: 9a9982ec (PG 15.16), 7a7d9693 (PG 17.8).
-- pgcrypto is default-enabled on Supabase, so this path is customer-reachable.
--
-- This is a functional + crash-safety regression: a valid round-trip still works,
-- and a malformed PGP packet raises a clean SQL error instead of crashing the
-- backend. (The public-key variant needs externally-generated GPG keys, so we
-- exercise the shared packet parser via the symmetric bytea path.)
--
-- Refs: PSQL-1110, PSQL-1234.

BEGIN;

-- 1) Happy path: symmetric PGP bytea round-trip returns the original plaintext.
SELECT pgp_sym_decrypt_bytea(
         pgp_sym_encrypt_bytea('\xdeadbeef'::bytea, 'test-key'),
         'test-key') = '\xdeadbeef'::bytea AS roundtrip_ok;

-- 2) A malformed PGP packet must raise a clean error, not crash the backend
--    (exercises the hardened packet-length parser).
SAVEPOINT malformed;
SELECT pgp_sym_decrypt_bytea('\xdeadbeefcafebabe'::bytea, 'test-key');
ROLLBACK TO SAVEPOINT malformed;

-- 3) Backend is still alive and pgcrypto still works after the error.
SELECT pgp_sym_decrypt(pgp_sym_encrypt('still-here', 'k'), 'k') AS post_error_ok;

ROLLBACK;
