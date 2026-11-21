-- Seed: a week of realistic searches so the analytics pipeline has data.
-- Re-run anytime to refresh. Safe: it only INSERTs (search_log has no
-- unique keyword constraint, so duplicates are fine — real logs duplicate too).

-- A few searches spread across the last 7 days.
-- SRCH_ID values are hand-picked 6-char codes that don't clash with
-- existing rows (we check with a SELECT first next to each batch).
-- USR_ID = '0AIFOA' (buyer) — must be a real user (foreign key rule).

INSERT INTO search_log (SRCH_ID, SRCH_KEYWORD, SRCH_FILTERS, SRCH_CREATED_AT, USR_ID) VALUES
('T1A01A', 'tomato',  NULL, DATE_SUB(NOW(), INTERVAL 1 HOUR),  '0AIFOA'),
('T1A02B', 'tomato',  NULL, DATE_SUB(NOW(), INTERVAL 3 HOUR),  '0AIFOA'),
('T1A03C', 'tomato',  NULL, DATE_SUB(NOW(), INTERVAL 1 DAY),   '0AIFOA'),
('T1A04D', 'pechay',  NULL, DATE_SUB(NOW(), INTERVAL 5 HOUR),  '0AIFOA'),
('T1A05E', 'pechay',  NULL, DATE_SUB(NOW(), INTERVAL 1 DAY),   '0AIFOA'),
('T1A06F', 'sitaw',   NULL, DATE_SUB(NOW(), INTERVAL 2 DAY),   '0AIFOA'),
('T1A07G', 'sitaw',   NULL, DATE_SUB(NOW(), INTERVAL 2 DAY),   '0AIFOA'),
('T1A08H', 'carrot',  NULL, DATE_SUB(NOW(), INTERVAL 3 DAY),   '0AIFOA'),
('T1A09I', 'eggplant',NULL, DATE_SUB(NOW(), INTERVAL 4 DAY),   '0AIFOA'),
('T1A10J', 'basil',   NULL, DATE_SUB(NOW(), INTERVAL 4 DAY),   '0AIFOA'),
('T1A11K', 'cabbage', NULL, DATE_SUB(NOW(), INTERVAL 5 DAY),   '0AIFOA'),
('T1A12L', 'tomato',  NULL, DATE_SUB(NOW(), INTERVAL 6 DAY),   '0AIFOA'),
('T1A13M', 'carrot',  NULL, DATE_SUB(NOW(), INTERVAL 6 DAY),   '0AIFOA');