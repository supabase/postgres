-- What changed: to_char() with the V format multiplies by a power of ten.
-- For example, '999V99' turns 1.23 into 123.
-- With integer input, if the result overflowed the type, to_char() printed wrong digits without an error.
-- Now it fails with "integer out of range".
-- The test cases come from upstream int4.sql.
--
-- Who notices: formatting code that uses V on large integers, for example to show amounts in cents.
-- It used to print wrong values, sometimes negative.
-- Now it fails.
-- To fix: cast the input to numeric first.
--
-- Upstream commits: 772251744 (PG 15.20), 04c25af21 (PG 17.12).

SELECT to_char(2, '9V999999999');           -- 2 * 10^9 fits
SELECT to_char(214748364, '999999999V9');   -- 2147483640 fits
SELECT to_char(-2, '9V999999999');          -- fits

-- These overflow int4 and must now error.
SELECT to_char(3, '9V999999999');
SELECT to_char(2147483647, '9V9');
SELECT to_char(1, '9V9999999999');
