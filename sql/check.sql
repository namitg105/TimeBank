-- =====================================================================
--  TimeBank -- LIVE CHECK
--
--     @check.sql
--
--  Run this once BEFORE you insert anything from the Flutter app, and
--  again AFTER. The numbers move, and the new rows appear at the top.
--
--  It is read-only. Run it as often as you like.
-- =====================================================================

SET LINESIZE 150
SET PAGESIZE 60
SET FEEDBACK OFF

PROMPT
PROMPT ================== ROW COUNTS ==================

SELECT 'STUDENT'       AS table_name, COUNT(*) AS rows_now FROM student
UNION ALL SELECT 'STUDENT_PHONE', COUNT(*) FROM student_phone
UNION ALL SELECT 'TUTOR',         COUNT(*) FROM tutor
UNION ALL SELECT 'TUTEE',         COUNT(*) FROM tutee
UNION ALL SELECT 'BOOKING',       COUNT(*) FROM booking
UNION ALL SELECT 'CREDIT_TXN',    COUNT(*) FROM credit_txn;

PROMPT
PROMPT ========== NEWEST 5 STUDENTS (newest first) ==========

SELECT student_id,
       reg_no,
       first_name || ' ' || last_name  AS full_name,
       email,
       account_status
FROM   (SELECT * FROM student ORDER BY student_id DESC)
WHERE  ROWNUM <= 5;

PROMPT
PROMPT ========== NEWEST 5 LEDGER ROWS (newest first) ==========

SELECT t.txn_id,
       s.first_name || ' ' || s.last_name  AS student,
       t.txn_type,
       t.amount,
       t.balance_snapshot,
       t.remarks
FROM   (SELECT * FROM credit_txn ORDER BY txn_id DESC) t
       JOIN student s ON s.student_id = t.student_id
WHERE  ROWNUM <= 5;

PROMPT
PROMPT ========== PHONE NUMBERS OF THE NEWEST STUDENT ==========

SELECT p.student_id, p.phone_no
FROM   student_phone p
WHERE  p.student_id = (SELECT MAX(student_id) FROM student);

PROMPT
PROMPT ========== CLOSED-ECONOMY AUDIT ==========

SELECT bal.total_balances,
       esc.in_escrow,
       grt.net_issued,
       bal.total_balances + esc.in_escrow - grt.net_issued AS drift,
       CASE WHEN bal.total_balances + esc.in_escrow = grt.net_issued
            THEN 'BALANCED' ELSE 'DRIFT -- INVESTIGATE' END AS verdict
FROM   (SELECT NVL(SUM(amount),0) AS total_balances FROM credit_txn) bal,
       (SELECT NVL(SUM(credits_held),0) AS in_escrow
        FROM   booking WHERE status IN ('CONFIRMED','REQUESTED')) esc,
       (SELECT NVL(SUM(CASE WHEN txn_type IN ('GRANT','PENALTY')
                            THEN amount ELSE 0 END),0) AS net_issued
        FROM   credit_txn) grt;

SET FEEDBACK ON

PROMPT
PROMPT  Register a student in the app, then run  @check.sql  again.
PROMPT  STUDENT +1, CREDIT_TXN +1, STUDENT_PHONE +1 -- all from one click.
PROMPT
