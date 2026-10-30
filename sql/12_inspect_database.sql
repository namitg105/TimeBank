-- =====================================================================
--  TimeBank
--  File    : 12_inspect_database.sql
--  Purpose : Show everything that is actually STORED inside the
--            database -- tables, columns, constraints, indexes, and the
--            SQL held in views, triggers and the package.
--
--  WHY THIS FILE EXISTS
--  The 45 queries in files 06 to 10 are SCRIPTS. Oracle runs them and
--  forgets them; they live in .sql files on disk, not in the database.
--
--  But a good deal of SQL IS stored permanently:
--     a VIEW is a stored SELECT
--     a TRIGGER is stored PL/SQL that fires on an event
--     a PACKAGE is stored PL/SQL you call by name
--
--  Oracle keeps all of it in the DATA DICTIONARY -- a set of catalog
--  views whose names start with USER_ (objects you own), ALL_ (objects
--  you can see) or DBA_ (everything, for administrators).
--
--  The data dictionary is the database describing itself, and it is
--  Module 1's three-schema architecture made concrete: these views are
--  the conceptual schema, readable as ordinary tables.
--
--  Run this to browse the schema without clicking through SQL Developer.
-- =====================================================================

SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 500
SET LONG 90000          -- view and trigger text are LONG columns
SET LONGCHUNKSIZE 90000


-- #####################################################################
--  1. EVERY OBJECT WE OWN
--  The one-screen summary of what the build scripts created.
-- #####################################################################
PROMPT
PROMPT ============================================================
PROMPT  1. ALL OBJECTS IN THIS SCHEMA
PROMPT ============================================================

SELECT object_type,
       COUNT (*)                                   AS how_many,
       SUM (CASE WHEN status = 'VALID'
                 THEN 0 ELSE 1 END)                AS invalid
FROM   user_objects
GROUP  BY object_type
ORDER  BY object_type;

PROMPT
PROMPT -- invalid should be 0 everywhere. If not, list them:

SELECT object_type, object_name, status
FROM   user_objects
WHERE  status <> 'VALID'
ORDER  BY object_type, object_name;


-- #####################################################################
--  2. THE TABLES, WITH ROW COUNTS
--  NUM_ROWS comes from the optimiser statistics gathered at the end of
--  02_indexes.sql. It is an estimate used for planning, not a live
--  count -- which is why a COUNT(*) is shown beside it for the main
--  tables.
-- #####################################################################
PROMPT
PROMPT ============================================================
PROMPT  2. TABLES
PROMPT ============================================================

SELECT table_name,
       num_rows        AS stats_rows,
       iot_type        AS index_organised
FROM   user_tables
ORDER  BY table_name;

PROMPT
PROMPT -- live row counts --

SELECT 'DEPARTMENT'     AS table_name, COUNT(*) AS live_rows FROM department
UNION ALL SELECT 'STUDENT',        COUNT(*) FROM student
UNION ALL SELECT 'STUDENT_PHONE',  COUNT(*) FROM student_phone
UNION ALL SELECT 'TUTOR',          COUNT(*) FROM tutor
UNION ALL SELECT 'TUTEE',          COUNT(*) FROM tutee
UNION ALL SELECT 'TUTEE_PREFTIME', COUNT(*) FROM tutee_preftime
UNION ALL SELECT 'SUBJECT',        COUNT(*) FROM subject
UNION ALL SELECT 'TUTOR_SKILL',    COUNT(*) FROM tutor_skill
UNION ALL SELECT 'SLOT',           COUNT(*) FROM slot
UNION ALL SELECT 'BOOKING',        COUNT(*) FROM booking
UNION ALL SELECT 'FEEDBACK',       COUNT(*) FROM feedback
UNION ALL SELECT 'ADMIN',          COUNT(*) FROM admin
UNION ALL SELECT 'DISPUTE',        COUNT(*) FROM dispute
UNION ALL SELECT 'CREDIT_TXN',     COUNT(*) FROM credit_txn
UNION ALL SELECT 'CREDIT_POLICY',  COUNT(*) FROM credit_policy
ORDER  BY table_name;


-- #####################################################################
--  3. COLUMNS OF EVERY TABLE
--  This is the relational schema, read straight out of the database.
--  Compare it against the A3 mapping sheet -- they should match
--  column for column.
-- #####################################################################
PROMPT
PROMPT ============================================================
PROMPT  3. COLUMNS
PROMPT ============================================================

SELECT t.table_name,
       c.column_id                  AS pos,
       c.column_name,
       c.data_type
         || CASE
              WHEN c.data_type IN ('VARCHAR2','CHAR')
                THEN '(' || c.data_length || ')'
              WHEN c.data_type = 'NUMBER' AND c.data_precision IS NOT NULL
                THEN '(' || c.data_precision ||
                     CASE WHEN NVL (c.data_scale, 0) > 0
                          THEN ',' || c.data_scale END || ')'
            END                     AS datatype,
       c.nullable                   AS nullable,
       c.data_default               AS default_value
FROM   user_tab_columns c
       JOIN user_tables t ON t.table_name = c.table_name
ORDER  BY t.table_name, c.column_id;


-- #####################################################################
--  4. PRIMARY KEYS
--  LISTAGG rebuilds a composite key into one readable line, in column
--  order. Four of these are composite -- the weak entities and the M:N
--  bridge.
-- #####################################################################
PROMPT
PROMPT ============================================================
PROMPT  4. PRIMARY KEYS
PROMPT ============================================================

SELECT c.table_name,
       c.constraint_name,
       LISTAGG (cc.column_name, ', ')
         WITHIN GROUP (ORDER BY cc.position)  AS key_columns,
       COUNT (*)                              AS col_count
FROM   user_constraints c
       JOIN user_cons_columns cc
         ON cc.constraint_name = c.constraint_name
WHERE  c.constraint_type = 'P'
GROUP  BY c.table_name, c.constraint_name
ORDER  BY col_count DESC, c.table_name;


-- #####################################################################
--  5. FOREIGN KEYS  -- the relational schema diagram, as data
--  Each row here is one arrow on the Figure 9.2-style sheet.
--
--  Watch for:
--    * BOOKING appearing twice with TUTOR_ID in different pairs --
--      those are the two COMPOSITE foreign keys that share a column
--    * CREDIT_TXN -> BOOKING, the only one whose column is nullable
-- #####################################################################
PROMPT
PROMPT ============================================================
PROMPT  5. FOREIGN KEYS
PROMPT ============================================================

SELECT c.table_name                              AS child_table,
       LISTAGG (cc.column_name, ', ')
         WITHIN GROUP (ORDER BY cc.position)     AS child_columns,
       r.table_name                              AS parent_table,
       LISTAGG (rc.column_name, ', ')
         WITHIN GROUP (ORDER BY rc.position)     AS parent_columns,
       c.delete_rule                             AS on_delete
FROM   user_constraints c
       JOIN user_cons_columns cc ON cc.constraint_name = c.constraint_name
       JOIN user_constraints r   ON r.constraint_name  = c.r_constraint_name
       JOIN user_cons_columns rc ON rc.constraint_name = r.constraint_name
                                AND rc.position        = cc.position
WHERE  c.constraint_type = 'R'
GROUP  BY c.table_name, c.constraint_name, r.table_name, c.delete_rule
ORDER  BY c.table_name, child_columns;

PROMPT
PROMPT -- which FK columns allow NULL? (expect exactly two) --

SELECT c.table_name, cc.column_name, col.nullable
FROM   user_constraints c
       JOIN user_cons_columns cc ON cc.constraint_name = c.constraint_name
       JOIN user_tab_columns col ON col.table_name  = c.table_name
                                AND col.column_name = cc.column_name
WHERE  c.constraint_type = 'R'
AND    col.nullable = 'Y'
ORDER  BY c.table_name;


-- #####################################################################
--  6. CHECK CONSTRAINTS  -- the domain constraints from Module 1
--  SEARCH_CONDITION holds the actual expression. Oracle also creates a
--  system-named CHECK for every NOT NULL, which is filtered out here so
--  only the ones we wrote are listed.
-- #####################################################################
PROMPT
PROMPT ============================================================
PROMPT  6. CHECK CONSTRAINTS
PROMPT ============================================================

SELECT table_name,
       constraint_name,
       search_condition_vc    AS condition
FROM   user_constraints
WHERE  constraint_type = 'C'
AND    constraint_name NOT LIKE 'SYS\_%' ESCAPE '\'
ORDER  BY table_name, constraint_name;


-- #####################################################################
--  7. INDEXES  -- Module 3
--  Every one of these is a B+ tree. UNIQUENESS tells you which were
--  created automatically to enforce a primary or unique key, and which
--  we added for the query workload.
-- #####################################################################
PROMPT
PROMPT ============================================================
PROMPT  7. INDEXES
PROMPT ============================================================

SELECT i.index_name,
       i.table_name,
       i.index_type,
       i.uniqueness,
       LISTAGG (ic.column_name, ', ')
         WITHIN GROUP (ORDER BY ic.column_position) AS indexed_columns
FROM   user_indexes i
       JOIN user_ind_columns ic ON ic.index_name = i.index_name
GROUP  BY i.index_name, i.table_name, i.index_type, i.uniqueness
ORDER  BY i.table_name, i.index_name;

PROMPT
PROMPT -- the function-based index stores an expression, not a column --

SELECT index_name, column_expression
FROM   user_ind_expressions
ORDER  BY index_name;


-- #####################################################################
--  8. VIEWS  -- STORED SQL, part 1
--  A view IS a stored SELECT statement. Nothing is copied; the text is
--  kept and re-run every time the view is queried.
--
--  This is where the DERIVED attributes live. The ER diagram draws
--  CreditBalance, Age, TotalHoursTaught and AvgRatingAsTutor as dashed
--  ovals, mapping rule 6 says they become no column, and these views
--  are how they are served instead.
-- #####################################################################
PROMPT
PROMPT ============================================================
PROMPT  8. VIEWS -- stored SELECT statements
PROMPT ============================================================

SELECT view_name, text_length AS chars_of_sql
FROM   user_views
ORDER  BY view_name;

PROMPT
PROMPT -- the full SQL text of each view --

SELECT view_name, text AS stored_sql
FROM   user_views
ORDER  BY view_name;


-- #####################################################################
--  9. TRIGGERS  -- STORED SQL, part 2
--  A trigger is PL/SQL stored against a table and fired by an event.
--  Nobody calls it; the database runs it.
-- #####################################################################
PROMPT
PROMPT ============================================================
PROMPT  9. TRIGGERS
PROMPT ============================================================

SELECT trigger_name,
       table_name,
       trigger_type,
       triggering_event,
       status
FROM   user_triggers
ORDER  BY table_name, trigger_name;

PROMPT
PROMPT -- the full body of each trigger --

SELECT trigger_name,
       trigger_body
FROM   user_triggers
ORDER  BY trigger_name;


-- #####################################################################
-- 10. THE PACKAGE  -- STORED SQL, part 3
--  USER_SOURCE holds stored PL/SQL one line per row, which is how
--  Oracle reports compilation errors by line number.
--
--  PKG_TIMEBANK is where the escrow lifecycle lives: book_session,
--  check_in, confirm_session, cancel_booking, raise_dispute,
--  resolve_dispute and audit_economy.
-- #####################################################################
PROMPT
PROMPT ============================================================
PROMPT 10. STORED PL/SQL
PROMPT ============================================================

SELECT name, type, MAX (line) AS lines_of_code
FROM   user_source
GROUP  BY name, type
ORDER  BY name, type;

PROMPT
PROMPT -- the package SPECIFICATION: what you can call --

SELECT line, text
FROM   user_source
WHERE  name = 'PKG_TIMEBANK'
AND    type = 'PACKAGE'
ORDER  BY line;

PROMPT
PROMPT -- to read the whole package BODY, run:
PROMPT    SELECT line, text FROM user_source
PROMPT    WHERE name = 'PKG_TIMEBANK' AND type = 'PACKAGE BODY'
PROMPT    ORDER BY line;


-- #####################################################################
-- 11. SEQUENCES
-- #####################################################################
PROMPT
PROMPT ============================================================
PROMPT 11. SEQUENCES
PROMPT ============================================================

SELECT sequence_name, min_value, increment_by, last_number
FROM   user_sequences
ORDER  BY sequence_name;


-- #####################################################################
-- 12. WHAT ORACLE REMEMBERS ABOUT QUERIES THAT HAVE RUN
--
--  Your SELECT statements are not stored objects -- but Oracle does
--  keep recently executed SQL in the shared pool, with its execution
--  statistics. This is how a DBA finds the slow queries on a live
--  system, and it is the closest thing to "the queries, in the
--  database".
--
--  The rows disappear when the statement is aged out of the pool, so
--  this is a cache, not a record.
--
--  Needs SELECT on V$SQL. If it fails with ORA-00942, ask whoever has
--  the SYSTEM password to run:
--     GRANT SELECT ON v_$sql TO timebank;
-- #####################################################################
PROMPT
PROMPT ============================================================
PROMPT 12. RECENTLY EXECUTED SQL (from the shared pool)
PROMPT ============================================================

SELECT *
FROM  (SELECT SUBSTR (sql_text, 1, 90)           AS sql_preview,
              executions,
              ROUND (elapsed_time/1000000, 3)    AS seconds_total,
              buffer_gets                        AS blocks_read
       FROM   v$sql
       WHERE  parsing_schema_name = USER
       AND    UPPER (sql_text) LIKE 'SELECT%'
       ORDER  BY elapsed_time DESC)
WHERE  ROWNUM <= 15;


PROMPT
PROMPT ============================================================
PROMPT  SUMMARY
PROMPT ============================================================
PROMPT
PROMPT  STORED in the database   : tables, columns, constraints,
PROMPT                             indexes, sequences, 3 views,
PROMPT                             6 triggers, 1 package
PROMPT
PROMPT  NOT stored               : the 45 SELECT/INSERT/UPDATE/DELETE
PROMPT                             statements in files 06 to 10. Those
PROMPT                             are scripts -- Oracle runs them and
PROMPT                             forgets them.
PROMPT
PROMPT  Section 12 above is the exception: Oracle caches recently run
PROMPT  statements in memory, but that is a performance cache, not
PROMPT  permanent storage.
PROMPT
