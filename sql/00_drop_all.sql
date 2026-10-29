-- =====================================================================
--  TimeBank : A Peer Tutoring Credit Exchange Management System
--  File    : 00_drop_all.sql
--  Purpose : Drop every object so the build scripts can be re-run.
--  Run     : FIRST, and only when rebuilding from scratch.
--  Note    : Errors like "table or view does not exist" are harmless on
--            the very first run -- nothing exists yet to drop.
-- =====================================================================

SET SERVEROUTPUT ON

-- Drop in reverse dependency order (children before parents).
BEGIN
  FOR r IN (
      SELECT table_name
      FROM   user_tables
      WHERE  table_name IN (
               'CREDIT_TXN','DISPUTE','FEEDBACK','BOOKING','SLOT',
               'TUTOR_SKILL','TUTEE_PREFTIME','TUTEE','TUTOR',
               'STUDENT_PHONE','SUBJECT','STUDENT','DEPARTMENT','ADMIN')
  ) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || r.table_name || ' CASCADE CONSTRAINTS PURGE';
    DBMS_OUTPUT.PUT_LINE('Dropped table  : ' || r.table_name);
  END LOOP;
END;
/

BEGIN
  FOR r IN (
      SELECT sequence_name
      FROM   user_sequences
      WHERE  sequence_name LIKE 'SEQ_%'
  ) LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE ' || r.sequence_name;
    DBMS_OUTPUT.PUT_LINE('Dropped seq    : ' || r.sequence_name);
  END LOOP;
END;
/

BEGIN
  FOR r IN (
      SELECT view_name FROM user_views WHERE view_name LIKE 'V\_%' ESCAPE '\'
  ) LOOP
    EXECUTE IMMEDIATE 'DROP VIEW ' || r.view_name;
    DBMS_OUTPUT.PUT_LINE('Dropped view   : ' || r.view_name);
  END LOOP;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP PACKAGE PKG_TIMEBANK';
  DBMS_OUTPUT.PUT_LINE('Dropped package: PKG_TIMEBANK');
EXCEPTION
  WHEN OTHERS THEN NULL;   -- package may not exist yet
END;
/

PROMPT ===> Schema cleared.
