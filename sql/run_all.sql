-- =====================================================================
--  TimeBank -- master build script
--
--  Run this ONE file to build the whole database from nothing:
--
--     sqlplus timebank/timebank@//localhost:1521/XE @run_all.sql
--
--  or open it in SQL Developer and press F5 (Run Script).
--
--  Order matters and is not negotiable:
--    00  clear anything already there
--    01  tables, constraints, sequences, views
--    02  indexes + the credit_policy table the triggers read
--    03  triggers (they reference credit_policy, so 02 must come first)
--    04  the PL/SQL package
--    05  seed data (calls the package, so 04 must come first)
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET ECHO OFF
WHENEVER SQLERROR CONTINUE

PROMPT
PROMPT #####################################################
PROMPT #  TimeBank -- building the database                #
PROMPT #####################################################

PROMPT
PROMPT [1/6] Clearing any previous build...
@@00_drop_all.sql

PROMPT
PROMPT [2/6] Creating tables, constraints and views...
@@01_ddl.sql

PROMPT
PROMPT [3/6] Creating indexes and policy settings...
@@02_indexes.sql

PROMPT
PROMPT [4/6] Compiling triggers...
@@03_triggers.sql

PROMPT
PROMPT [5/6] Compiling PKG_TIMEBANK...
@@04_packages.sql

PROMPT
PROMPT [6/6] Loading seed data...
@@05_seed.sql

PROMPT
PROMPT #####################################################
PROMPT #  Build finished. Checking for invalid objects...  #
PROMPT #####################################################

SELECT object_type, object_name, status
FROM   user_objects
WHERE  status <> 'VALID'
ORDER  BY object_type, object_name;

PROMPT
PROMPT (No rows above = everything compiled cleanly.)
PROMPT
PROMPT Now run the five member files in order -- each one builds on the
PROMPT data the previous one created, so the sequence matters:
PROMPT
PROMPT   @06_member1_onboarding.sql          Member 1
PROMPT   @07_member2_skills.sql              Member 2
PROMPT   @08_member3_booking.sql             Member 3
PROMPT   @09_member4_credit.sql              Member 4
PROMPT   @10_member5_feedback_disputes.sql   Member 5
PROMPT   @11_group_tcl_plans.sql             everyone, together
PROMPT
PROMPT Each member file holds exactly 9 queries: 1 INSERT, 1 UPDATE,
PROMPT 1 DELETE and 6 SELECTs (simple, join, nested, correlated,
PROMPT aggregate, analytic). See QUERY_PLAN.md for the full breakdown.
PROMPT
