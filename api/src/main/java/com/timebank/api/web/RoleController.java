package com.timebank.api.web;

import com.timebank.dao.RoleDao;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.sql.SQLException;
import java.util.List;
import java.util.Map;

/**
 * Enrolment into the two subclasses, over HTTP.
 *
 * <p>There is deliberately no single "set my role" endpoint. Becoming a
 * mentor and becoming a mentee are independent operations because the
 * specialization is <b>overlapping</b> — one person may legitimately be
 * both — and <b>partial</b>, so being neither is also valid. A single
 * endpoint taking one role would quietly make it disjoint and total.
 */
@RestController
@RequestMapping("/api/roles")
public class RoleController {

    private final RoleDao dao = new RoleDao();

    /** GET /api/roles/105 — which subclasses this student is already in. */
    @GetMapping("/{studentId}")
    public Map<String, Object> roleOf(@PathVariable int studentId)
            throws SQLException {
        RoleDao.RoleState st = dao.roleOf(studentId);
        return Map.of(
                "studentId", studentId,
                "isTutor",   st.isTutor(),
                "isTutee",   st.isTutee(),
                "badgeLevel", st.badgeLevel() == null ? "" : st.badgeLevel(),
                "needTier",   st.needTier()   == null ? "" : st.needTier(),
                "label",      st.label());
    }

    /** GET /api/roles/subjects — the catalogue, for the subject picker. */
    @GetMapping("/subjects")
    public List<RoleDao.Subject> subjects() throws SQLException {
        return dao.subjects();
    }

    /**
     * POST /api/roles/105/tutor — become a mentor.
     *
     * <p>Body: verificationDocNo, and optionally subjectId, competency
     * and grade for the first subject they can teach.
     */
    @PostMapping("/{studentId}/tutor")
    public ResponseEntity<Map<String, Object>> becomeTutor(
            @PathVariable int studentId,
            @RequestBody Map<String, Object> body) throws SQLException {

        String doc = str(body.get("verificationDocNo"));
        if (doc == null) {
            throw new IllegalArgumentException(
                    "A verification document number is required to teach.");
        }

        Integer subjectId  = intOrNull(body.get("subjectId"));
        String  competency = str(body.get("competency"));
        String  grade      = str(body.get("grade"));

        if (subjectId != null) {
            competency = competency == null ? "PROFICIENT"
                                            : competency.toUpperCase();
            grade      = grade      == null ? "A" : grade.toUpperCase();
            requireOneOf(competency, "competency",
                         "BEGINNER", "PROFICIENT", "EXPERT");
            requireOneOf(grade, "grade", "S", "A", "B", "C");
        }

        dao.becomeTutor(studentId, doc, subjectId, competency, grade);

        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of(
                "studentId", studentId,
                "role", "TUTOR",
                "badgeLevel", "BRONZE",
                "message", "Enrolled as a mentor. Badge starts at BRONZE and "
                         + "is raised automatically by the database as hours "
                         + "are taught."));
    }

    /** POST /api/roles/105/skills — another subject this tutor can teach. */
    @PostMapping("/{studentId}/skills")
    public Map<String, Object> addSkill(@PathVariable int studentId,
                                        @RequestBody Map<String, Object> body)
            throws SQLException {

        Integer subjectId = intOrNull(body.get("subjectId"));
        if (subjectId == null) {
            throw new IllegalArgumentException("subjectId is required.");
        }
        String competency = orDefault(str(body.get("competency")), "PROFICIENT");
        String grade      = orDefault(str(body.get("grade")), "A");

        requireOneOf(competency, "competency", "BEGINNER", "PROFICIENT", "EXPERT");
        requireOneOf(grade, "grade", "S", "A", "B", "C");

        dao.addSkill(studentId, subjectId, competency, grade);
        return Map.of("added", true, "subjectId", subjectId);
    }

    /** POST /api/roles/105/slots — publish an availability slot. */
    @PostMapping("/{studentId}/slots")
    public Map<String, Object> addSlot(@PathVariable int studentId,
                                       @RequestBody Map<String, Object> body)
            throws SQLException {

        String day = orDefault(str(body.get("dayOfWeek")), "").toUpperCase();
        requireOneOf(day, "dayOfWeek",
                     "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN");

        Integer start = intOrNull(body.get("startTime"));
        Integer end   = intOrNull(body.get("endTime"));
        if (start == null || end == null || end <= start) {
            throw new IllegalArgumentException(
                    "startTime and endTime are required, and endTime must be later.");
        }

        dao.addSlot(studentId, day, start, end);
        return Map.of("added", true, "dayOfWeek", day,
                      "startTime", start, "endTime", end);
    }

    /**
     * POST /api/roles/105/tutee — become a mentee.
     *
     * <p>Body: needTier, and optionally timeBands.
     */
    @PostMapping("/{studentId}/tutee")
    @SuppressWarnings("unchecked")
    public ResponseEntity<Map<String, Object>> becomeTutee(
            @PathVariable int studentId,
            @RequestBody Map<String, Object> body) throws SQLException {

        String tier = orDefault(str(body.get("needTier")), "BASIC").toUpperCase();
        requireOneOf(tier, "needTier", "BASIC", "INTERMEDIATE", "ADVANCED");

        List<String> bands = List.of();
        Object raw = body.get("timeBands");
        if (raw instanceof List<?> list) {
            bands = list.stream().map(o -> String.valueOf(o).toUpperCase()).toList();
            for (String b : bands) {
                requireOneOf(b, "timeBand",
                             "MORNING", "AFTERNOON", "EVENING", "NIGHT");
            }
            bands = (List<String>) (List<?>) bands;
        }

        dao.becomeTutee(studentId, tier, bands);

        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of(
                "studentId", studentId,
                "role", "TUTEE",
                "needTier", tier,
                "message", "Enrolled as a mentee. You can book sessions now."));
    }

    // -----------------------------------------------------------------

    private static String str(Object o) {
        if (o == null) {
            return null;
        }
        String s = String.valueOf(o).trim();
        return s.isEmpty() ? null : s;
    }

    private static String orDefault(String s, String fallback) {
        return s == null ? fallback : s;
    }

    private static Integer intOrNull(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Number n) {
            return n.intValue();
        }
        try {
            return Integer.valueOf(String.valueOf(o).trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static void requireOneOf(String value, String field,
                                     String... allowed) {
        for (String a : allowed) {
            if (a.equals(value)) {
                return;
            }
        }
        throw new IllegalArgumentException(
                field + " must be one of " + String.join(", ", allowed)
              + " (got " + value + ").");
    }
}
