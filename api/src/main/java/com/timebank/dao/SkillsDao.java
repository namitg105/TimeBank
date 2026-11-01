package com.timebank.dao;

import com.timebank.db.Database;
import com.timebank.db.SqlLog;

import java.sql.*;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Skills and availability.
 *
 * <p>MEMBER 2 — SUBJECT, TUTOR_SKILL, SLOT.
 *
 * <p>THE THREE IDEAS THIS MODULE OWNS
 *
 * <ul>
 *   <li><b>The M:N relationship.</b> A tutor teaches many subjects and
 *       a subject has many tutors, so <i>offers</i> cannot be a column
 *       on either table. TUTOR_SKILL exists because of that — and its
 *       three attributes (competency_level, grade_proof, certified_on)
 *       describe one tutor's claim on one subject, so they belong on
 *       the relationship rather than on TUTOR or SUBJECT.</li>
 *
 *   <li><b>Weak entities and partial keys.</b> SLOT has no identity of
 *       its own. {@code slot_no} restarts at 1 for every tutor, so it
 *       is a PARTIAL key and the real primary key is the pair
 *       (tutor_id, slot_no).</li>
 *
 *   <li><b>Cross-department tutoring.</b> The schema never says a tutor
 *       may only teach their own department's subjects, and the data
 *       shows why that would be wrong — Rohan is Mechanical and teaches
 *       Database Systems.</li>
 * </ul>
 */
public class SkillsDao {

    // -----------------------------------------------------------------
    //  Q2 — the skill matrix  (five tables)
    // -----------------------------------------------------------------

    /**
     * Who can teach what, with cross-department tutoring flagged.
     *
     * <p>Five tables. Two joins to DEPARTMENT under different aliases:
     * one for where the tutor belongs, one for which school owns the
     * subject. Comparing them is what detects cross-department
     * tutoring — a fact nothing stores, because it is a relationship
     * between two other facts.
     */
    public List<Map<String, Object>> skillMatrix(Integer tutorId)
            throws SQLException {

        String sql = """
                SELECT ts.tutor_id,
                       s.first_name || ' ' || s.last_name  AS tutor_name,
                       td.school                           AS tutor_school,
                       sub.subject_id,
                       sub.subject_code,
                       sub.subject_name,
                       sd.school                           AS subject_school,
                       ts.competency_level,
                       ts.grade_proof,
                       TO_CHAR(ts.certified_on,'DD-MON-YYYY') AS certified_on,
                       CASE WHEN td.school <> sd.school
                            THEN 'CROSS-DEPARTMENT' ELSE 'own department'
                       END                                 AS note
                FROM   tutor_skill ts
                       JOIN student    s   ON s.student_id   = ts.tutor_id
                       JOIN department td  ON td.dept_id     = s.dept_id
                       JOIN subject    sub ON sub.subject_id = ts.subject_id
                       JOIN department sd  ON sd.dept_id     = sub.dept_id
                WHERE  (? IS NULL OR ts.tutor_id = ?)
                ORDER  BY note, s.first_name, sub.subject_code""";

        long t0 = SqlLog.q("MEMBER 2  .  Who teaches what", sql, tutorId, tutorId);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql)) {

            if (tutorId == null) {
                ps.setNull(1, Types.INTEGER);
                ps.setNull(2, Types.INTEGER);
            } else {
                ps.setInt(1, tutorId);
                ps.setInt(2, tutorId);
            }

            try (ResultSet rs = ps.executeQuery()) {
                List<Map<String, Object>> out = rowsOf(rs);
                SqlLog.rows(out.size(), t0);
                return out;
            }
        }
    }

    // -----------------------------------------------------------------
    //  Q3 — subjects nobody can teach  (NOT IN)
    // -----------------------------------------------------------------

    /**
     * Subjects with no tutor at all — the gaps in the catalogue.
     *
     * <p>NOT IN is safe here only because {@code tutor_skill.subject_id}
     * is NOT NULL. That matters: a single NULL in the inner list makes
     * NOT IN return nothing at all, because comparing anything to NULL
     * yields UNKNOWN rather than TRUE, and UNKNOWN is not TRUE. NOT
     * EXISTS has no such trap, which is why the next query uses it.
     */
    public List<Map<String, Object>> subjectsWithNoTutor() throws SQLException {
        String sql = """
                SELECT sub.subject_code, sub.subject_name, sub.category,
                       d.school AS owning_school
                FROM   subject sub
                       JOIN department d ON d.dept_id = sub.dept_id
                WHERE  sub.subject_id NOT IN (SELECT subject_id
                                              FROM   tutor_skill)
                ORDER  BY sub.subject_code""";

        long t0 = SqlLog.q("MEMBER 2  .  Subjects with no tutor", sql);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            List<Map<String, Object>> out = rowsOf(rs);
            SqlLog.rows(out.size(), t0);
            return out;
        }
    }

    // -----------------------------------------------------------------
    //  Q4 — availability  (CORRELATED, NOT EXISTS)
    // -----------------------------------------------------------------

    /**
     * Every slot a tutor has published.
     *
     * <p>The flag uses NOT EXISTS, which mentions the outer row and so
     * is re-evaluated per slot — the correlation. Unlike NOT IN above,
     * it is unaffected by NULLs, and it stops at the first match rather
     * than building a whole list.
     */
    public List<Map<String, Object>> slotsOf(int tutorId) throws SQLException {
        String sql = """
                SELECT sl.tutor_id, sl.slot_no, sl.day_of_week,
                       sl.start_time, sl.end_time,
                       sl.end_time - sl.start_time AS hours_long,
                       CASE WHEN NOT EXISTS (SELECT 1
                                             FROM   booking b
                                             WHERE  b.tutor_id = sl.tutor_id
                                             AND    b.slot_no  = sl.slot_no
                                             AND    b.status IN ('REQUESTED',
                                                                 'CONFIRMED'))
                            THEN 'free' ELSE 'has a booking' END AS state
                FROM   slot sl
                WHERE  sl.tutor_id = ?
                ORDER  BY CASE sl.day_of_week
                            WHEN 'MON' THEN 1 WHEN 'TUE' THEN 2
                            WHEN 'WED' THEN 3 WHEN 'THU' THEN 4
                            WHEN 'FRI' THEN 5 WHEN 'SAT' THEN 6
                            ELSE 7 END,
                          sl.start_time""";

        long t0 = SqlLog.q("MEMBER 2  .  Free hours",
                sql, tutorId);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setInt(1, tutorId);
            try (ResultSet rs = ps.executeQuery()) {
                List<Map<String, Object>> out = rowsOf(rs);
                SqlLog.rows(out.size(), t0);
                return out;
            }
        }
    }

    // -----------------------------------------------------------------
    //  Q5 — capacity against demand  (AGGREGATE)
    // -----------------------------------------------------------------

    public List<Map<String, Object>> capacity() throws SQLException {
        String sql = """
                SELECT sub.subject_code, sub.subject_name,
                       COUNT(ts.tutor_id)                       AS tutors,
                       SUM(CASE WHEN ts.competency_level = 'EXPERT'
                                THEN 1 ELSE 0 END)              AS experts,
                       NVL(SUM(CASE WHEN ts.competency_level = 'EXPERT'
                                    THEN 1 ELSE 0 END), 0)      AS expert_count,
                       MIN(TO_CHAR(ts.certified_on,'DD-MON-YY')) AS first_certified
                FROM   subject sub
                       LEFT JOIN tutor_skill ts ON ts.subject_id = sub.subject_id
                GROUP  BY sub.subject_code, sub.subject_name
                HAVING COUNT(ts.tutor_id) >= 0
                ORDER  BY tutors DESC, sub.subject_code""";

        long t0 = SqlLog.q("MEMBER 2  .  Tutors per subject", sql);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            List<Map<String, Object>> out = rowsOf(rs);
            SqlLog.rows(out.size(), t0);
            return out;
        }
    }

    // -----------------------------------------------------------------
    //  DELETE — withdraw a slot
    // -----------------------------------------------------------------

    /**
     * Removes an availability slot.
     *
     * <p>Only a slot nobody has booked may go. A slot referenced by a
     * live BOOKING is protected by FK_BK_SLOT, and Oracle refuses —
     * deliberately, because deleting it would orphan a session that
     * already has credits in escrow.
     */
    public int removeSlot(int tutorId, int slotNo) throws SQLException {
        String sql = """
                DELETE FROM slot sl
                WHERE  sl.tutor_id = ?
                AND    sl.slot_no  = ?
                AND    NOT EXISTS (SELECT 1 FROM booking b
                                   WHERE  b.tutor_id = sl.tutor_id
                                   AND    b.slot_no  = sl.slot_no)""";

        long t0 = SqlLog.q("MEMBER 2  .  Remove free hours",
                sql, tutorId, slotNo);

        Connection c = null;
        try {
            c = Database.get();
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                ps.setInt(1, tutorId);
                ps.setInt(2, slotNo);
                int n = ps.executeUpdate();
                c.commit();
                SqlLog.changed(n, t0);

                Database.showAfter(
                    "SLOT for tutor " + tutorId + ":",
                    "SELECT tutor_id, slot_no, day_of_week, start_time, "
                  + "end_time FROM slot WHERE tutor_id = ? ORDER BY slot_no",
                    tutorId);

                return n;
            }
        } catch (SQLException e) {
            Database.silentRollback(c);
            SqlLog.failed(Database.explain(e), t0);
            throw e;
        } finally {
            if (c != null) c.close();
        }
    }

    /**
     * Raises or lowers a tutor's competency in one subject.
     *
     * <p>Both key columns are in the WHERE because TUTOR_SKILL's primary
     * key is the composite (tutor_id, subject_id) — one of them alone
     * identifies nothing.
     */
    public int setCompetency(int tutorId, int subjectId,
                             String level, String grade) throws SQLException {
        String sql = """
                UPDATE tutor_skill
                SET    competency_level = ?,
                       grade_proof      = ?
                WHERE  tutor_id   = ?
                AND    subject_id = ?""";

        long t0 = SqlLog.q("MEMBER 2  .  Change competency level",
                sql, level, grade, tutorId, subjectId);

        Connection c = null;
        try {
            c = Database.get();
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                ps.setString(1, level);
                ps.setString(2, grade);
                ps.setInt(3, tutorId);
                ps.setInt(4, subjectId);
                int n = ps.executeUpdate();
                c.commit();
                SqlLog.changed(n, t0);

                Database.showAfter(
                    "TUTOR_SKILL now reads:",
                    "SELECT tutor_id, subject_id, competency_level, "
                  + "grade_proof, certified_on FROM tutor_skill "
                  + "WHERE tutor_id = ? AND subject_id = ?",
                    tutorId, subjectId);

                return n;
            }
        } catch (SQLException e) {
            Database.silentRollback(c);
            SqlLog.failed(Database.explain(e), t0);
            throw e;
        } finally {
            if (c != null) c.close();
        }
    }

    // -----------------------------------------------------------------

    private static List<Map<String, Object>> rowsOf(ResultSet rs)
            throws SQLException {
        ResultSetMetaData meta = rs.getMetaData();
        int cols = meta.getColumnCount();

        List<Map<String, Object>> out = new ArrayList<>();
        while (rs.next()) {
            Map<String, Object> row = new LinkedHashMap<>();
            for (int i = 1; i <= cols; i++) {
                Object v = rs.getObject(i);
                row.put(camel(meta.getColumnLabel(i)),
                        v instanceof java.math.BigDecimal b
                            ? (Object) b.doubleValue()
                            : v == null ? null : String.valueOf(v));
            }
            out.add(row);
        }
        return out;
    }

    /** SUBJECT_CODE -> subjectCode, so the JSON reads naturally in Dart. */
    private static String camel(String column) {
        String[] parts = column.toLowerCase().split("_");
        StringBuilder sb = new StringBuilder(parts[0]);
        for (int i = 1; i < parts.length; i++) {
            if (parts[i].isEmpty()) {
                continue;
            }
            sb.append(Character.toUpperCase(parts[i].charAt(0)))
              .append(parts[i].substring(1));
        }
        return sb.toString();
    }
}
