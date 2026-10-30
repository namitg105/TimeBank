package com.timebank.dao;

import com.timebank.db.Database;
import com.timebank.db.SqlLog;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;

/**
 * Enrolment into the two subclasses: TUTOR and TUTEE.
 *
 * <p>THE ER POINT THIS CLASS EXISTS TO MAKE
 * STUDENT is specialised into TUTOR and TUTEE, and that specialization
 * is <b>overlapping</b> and <b>partial</b>:
 *
 * <ul>
 *   <li><b>overlapping</b> — the same student may be in both tables, so
 *       {@link #becomeTutor} and {@link #becomeTutee} are independent
 *       calls and nothing stops a person making both;</li>
 *   <li><b>partial</b> — a student need be in neither, which is why
 *       these are separate operations rather than part of registration.</li>
 * </ul>
 *
 * <p>Both subclass tables take {@code student_id} as their primary key
 * <em>and</em> as a foreign key to STUDENT. That is mapping option 8A
 * from the textbook, and it is what makes the 1:1 link to the superclass
 * enforceable rather than merely intended.
 */
public class RoleDao {

    public record Subject(int subjectId, String code, String name,
                          String category, String school) { }

    public record RoleState(boolean isTutor, boolean isTutee,
                            String badgeLevel, String needTier) {
        public String label() {
            if (isTutor && isTutee) return "BOTH";
            if (isTutor)            return "TUTOR ONLY";
            if (isTutee)            return "TUTEE ONLY";
            return "NEITHER YET";
        }
    }

    // -----------------------------------------------------------------
    //  Which roles does this student already hold?
    // -----------------------------------------------------------------

    /**
     * Two LEFT JOINs, exactly as in Member 1's Q2.
     *
     * <p>They must be OUTER. An inner join would drop any student who is
     * not in that subclass, and BOTH and NEITHER — the two categories
     * that prove the specialization is overlapping and partial — would
     * disappear with them.
     */
    public RoleState roleOf(int studentId) throws SQLException {
        String sql = """
                SELECT CASE WHEN t.student_id IS NULL THEN 0 ELSE 1 END AS is_tutor,
                       CASE WHEN e.student_id IS NULL THEN 0 ELSE 1 END AS is_tutee,
                       t.badge_level,
                       e.academic_need_tier
                FROM   student s
                       LEFT JOIN tutor t ON t.student_id = s.student_id
                       LEFT JOIN tutee e ON e.student_id = s.student_id
                WHERE  s.student_id = ?""";

        long t0 = SqlLog.q("RoleDao.roleOf  (the two LEFT JOINs of the"
                         + " overlapping, partial specialization)", sql, studentId);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setInt(1, studentId);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) {
                    SqlLog.rows(0, t0);
                    throw new IllegalArgumentException(
                            "No student with id " + studentId + ".");
                }
                RoleState st = new RoleState(
                        rs.getInt("is_tutor") == 1,
                        rs.getInt("is_tutee") == 1,
                        rs.getString("badge_level"),
                        rs.getString("academic_need_tier"));
                SqlLog.called("role = " + st.label(), t0);
                return st;
            }
        }
    }

    // -----------------------------------------------------------------
    //  Become a MENTOR (tutor)
    // -----------------------------------------------------------------

    /**
     * Enrols a student as a tutor, optionally with their first subject.
     *
     * <p>Both writes share one transaction. A tutor with no subject can
     * teach nothing, so creating the TUTOR row and the first
     * TUTOR_SKILL row together is the honest unit of work.
     *
     * <p>BADGE_LEVEL is not passed in and cannot be. It starts at BRONZE
     * and is maintained by the compound trigger TRG_BADGE_PROMOTE as
     * hours are actually taught — a tutor cannot award themselves GOLD.
     */
    public void becomeTutor(int studentId, String verificationDocNo,
                            Integer subjectId, String competency, String grade)
            throws SQLException {

        String sqlTutor = """
                INSERT INTO tutor (student_id, badge_level, verification_doc_no)
                VALUES (?, 'BRONZE', ?)""";

        String sqlSkill = """
                INSERT INTO tutor_skill (
                    tutor_id, subject_id, competency_level, grade_proof, certified_on)
                VALUES (?, ?, ?, ?, SYSDATE)""";

        long t0 = SqlLog.q("RoleDao.becomeTutor  (subclass enrolment; badge"
                         + " starts BRONZE and only the compound trigger may"
                         + " change it)", sqlTutor, studentId, verificationDocNo);

        Connection c = null;
        try {
            c = Database.get();

            try (PreparedStatement ps = c.prepareStatement(sqlTutor)) {
                ps.setInt(1, studentId);
                ps.setString(2, verificationDocNo);
                int n = ps.executeUpdate();
                SqlLog.changed(n, t0);
            }

            if (subjectId != null) {
                long t1 = SqlLog.q("RoleDao.becomeTutor  (first subject --"
                                 + " composite key (tutor_id, subject_id))",
                        sqlSkill, studentId, subjectId, competency, grade);
                try (PreparedStatement ps = c.prepareStatement(sqlSkill)) {
                    ps.setInt(1, studentId);
                    ps.setInt(2, subjectId);
                    ps.setString(3, competency);
                    ps.setString(4, grade);
                    int n = ps.executeUpdate();
                    SqlLog.changed(n, t1);
                }
            }

            c.commit();
        } catch (SQLException e) {
            Database.silentRollback(c);
            SqlLog.failed(Database.explain(e), t0);
            throw e;
        } finally {
            if (c != null) c.close();
        }
    }

    /** Adds one more subject an existing tutor can teach. */
    public void addSkill(int tutorId, int subjectId,
                         String competency, String grade) throws SQLException {

        String sql = """
                INSERT INTO tutor_skill (
                    tutor_id, subject_id, competency_level, grade_proof, certified_on)
                VALUES (?, ?, ?, ?, SYSDATE)""";

        long t0 = SqlLog.q("RoleDao.addSkill  (PK is the composite"
                         + " (tutor_id, subject_id), so the same subject"
                         + " cannot be claimed twice)",
                sql, tutorId, subjectId, competency, grade);

        Connection c = null;
        try {
            c = Database.get();
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                ps.setInt(1, tutorId);
                ps.setInt(2, subjectId);
                ps.setString(3, competency);
                ps.setString(4, grade);
                int n = ps.executeUpdate();
                c.commit();
                SqlLog.changed(n, t0);
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
     * Publishes an availability slot.
     *
     * <p>SLOT is a WEAK ENTITY: {@code slot_no} is only a partial key, so
     * it is unique within one tutor and meaningless without them. The
     * primary key is therefore the pair (tutor_id, slot_no), and the
     * next number has to be computed per tutor rather than drawn from a
     * sequence shared across everyone.
     */
    public int addSlot(int tutorId, String dayOfWeek,
                       int startTime, int endTime) throws SQLException {

        String sql = """
                INSERT INTO slot (tutor_id, slot_no, day_of_week, start_time, end_time)
                VALUES (?,
                        (SELECT NVL(MAX(slot_no),0) + 1 FROM slot WHERE tutor_id = ?),
                        ?, ?, ?)""";

        long t0 = SqlLog.q("RoleDao.addSlot  (SLOT is a WEAK ENTITY -- slot_no"
                         + " is a PARTIAL key, numbered per tutor, so the next"
                         + " value is computed inside the INSERT)",
                sql, tutorId, tutorId, dayOfWeek, startTime, endTime);

        Connection c = null;
        try {
            c = Database.get();
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                ps.setInt(1, tutorId);
                ps.setInt(2, tutorId);
                ps.setString(3, dayOfWeek);
                ps.setInt(4, startTime);
                ps.setInt(5, endTime);
                int n = ps.executeUpdate();
                c.commit();
                SqlLog.changed(n, t0);
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
    //  Become a MENTEE (tutee)
    // -----------------------------------------------------------------

    /**
     * Enrols a student as a tutee, with any preferred time bands.
     *
     * <p>PreferredTime was a MULTIVALUED attribute in the ER diagram, so
     * it became its own table keyed on (student_id, timeband) — which is
     * also what stops the same band being stored twice.
     */
    public void becomeTutee(int studentId, String needTier,
                            List<String> timeBands) throws SQLException {

        String sqlTutee = """
                INSERT INTO tutee (student_id, academic_need_tier)
                VALUES (?, ?)""";

        String sqlPref = """
                INSERT INTO tutee_preftime (student_id, preferred_timeband)
                VALUES (?, ?)""";

        long t0 = SqlLog.q("RoleDao.becomeTutee  (subclass enrolment)",
                sqlTutee, studentId, needTier);

        Connection c = null;
        try {
            c = Database.get();

            try (PreparedStatement ps = c.prepareStatement(sqlTutee)) {
                ps.setInt(1, studentId);
                ps.setString(2, needTier);
                int n = ps.executeUpdate();
                SqlLog.changed(n, t0);
            }

            if (timeBands != null && !timeBands.isEmpty()) {
                long t1 = SqlLog.q("RoleDao.becomeTutee  (PreferredTime was a"
                                 + " MULTIVALUED attribute, so it has its own"
                                 + " table -- one INSERT per band)",
                        sqlPref, studentId, String.join(", ", timeBands));

                int total = 0;
                try (PreparedStatement ps = c.prepareStatement(sqlPref)) {
                    for (String band : timeBands) {
                        ps.setInt(1, studentId);
                        ps.setString(2, band);
                        ps.addBatch();
                    }
                    for (int r : ps.executeBatch()) {
                        total += (r > 0 ? r : 1);
                    }
                }
                SqlLog.changed(total, t1);
            }

            c.commit();
        } catch (SQLException e) {
            Database.silentRollback(c);
            SqlLog.failed(Database.explain(e), t0);
            throw e;
        } finally {
            if (c != null) c.close();
        }
    }

    // -----------------------------------------------------------------
    //  Lookup lists for the pickers
    // -----------------------------------------------------------------

    public List<Subject> subjects() throws SQLException {
        String sql = """
                SELECT sub.subject_id, sub.subject_code, sub.subject_name,
                       sub.category, d.school
                FROM   subject sub
                       JOIN department d ON d.dept_id = sub.dept_id
                ORDER  BY sub.subject_code""";

        long t0 = SqlLog.q("RoleDao.subjects  (catalogue for the picker)", sql);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            List<Subject> out = new ArrayList<>();
            while (rs.next()) {
                out.add(new Subject(
                        rs.getInt("subject_id"),
                        rs.getString("subject_code"),
                        rs.getString("subject_name"),
                        rs.getString("category"),
                        rs.getString("school")));
            }
            SqlLog.rows(out.size(), t0);
            return out;
        }
    }
}
