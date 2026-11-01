-- =====================================================================
--  TimeBank -- FULL REBUILD AND DEMO, repeatable
--
--     cd C:\Users\gnami\Desktop\TimeBank\sql
--     sqlplus timebank/timebank@localhost:1521/XE "@rerun.sql"
--
--  WHY THIS FILE EXISTS
--    The five member files each start with an INSERT, so they are
--    written to run ONCE against a freshly seeded database.  Running
--    06 a second time tries to register Tanvi again and raises
--    ORA-00001 on UQ_STUDENT_REG; 07 would add a second copy of the
--    same tutor; 08 would create another booking.  The data drifts a
--    little further from the seed on every pass.
--
--    So this file does not try to make those statements repeatable.
--    It drops the whole schema, rebuilds it, reseeds it, and only then
--    runs the member files.  Every run therefore starts from the same
--    place and produces the same output, with no errors.
--
--  SAFE TO RUN AS OFTEN AS YOU LIKE.  It only ever touches the
--  TIMEBANK schema.
--
--  Everything is also written to demo_output.txt in this folder, so
--  you have a transcript for the report without re-running anything.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 100
SET DEFINE OFF
SET ECHO OFF
SET TRIMSPOOL ON
WHENEVER SQLERROR CONTINUE

SPOOL demo_output.txt

PROMPT
PROMPT #####################################################
PROMPT #  STEP 1 of 2  --  rebuilding from scratch         #
PROMPT #####################################################

@@run_all.sql

PROMPT
PROMPT #####################################################
PROMPT #  STEP 2 of 2  --  the 45 queries, five members    #
PROMPT #####################################################

@@onboarding.sql
@@07_member2_skills.sql
@@08_member3_booking.sql
@@09_member4_credit.sql
@@10_member5_feedback_disputes.sql
@@11_group_tcl_plans.sql

PROMPT
PROMPT #####################################################
PROMPT #  FINISHED                                         #
PROMPT #####################################################
PROMPT
PROMPT   Transcript saved to demo_output.txt in this folder.
PROMPT
PROMPT   The only ORA- errors you should have seen are the two
PROMPT   deliberate ones in Member 4, each printed as
PROMPT   "Blocked as designed -> ORA-20001".  Those are the
PROMPT   append-only trigger proving the ledger cannot be edited.
PROMPT
PROMPT   Anything else is a real failure -- read it, do not ignore it.
PROMPT

SPOOL OFF
