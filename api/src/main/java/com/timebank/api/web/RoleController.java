package com.timebank.api.web;

import com.timebank.dao.RoleDao;
import com.timebank.dao.StudentLookup;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Enrolment into the two subclasses, over HTTP.
 *
 * <p>There is deliberately no single "set my role" endpoint. Becoming a
 * tutor and becoming a learner are independent operations because the
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
     * POST /api/roles/105/tutor — become a tutor.
     *
     * <p>Body: verificationDocNo, subjectId, and optionally competency
     * and grade for the first subject they can teach.
     */
    @PostMapping("/{studentId}/tutor")
    public ResponseEntity<Map<String, Object>> becomeTutor(
            @PathVariable int studentId,
            @RequestBody Map<String, Object> body) throws SQLException {

        StudentLookup.requireExists(studentId);
        if (dao.roleOf(studentId).isTutor()) {
            throw new IllegalArgumentException("You are already a tutor.");
        }

        String doc = Input.maxLength(
                Input.required(body.get("verificationDocNo"),
                        "Enter a verification document number."),
                30, "Verification document number");
        int subjectId = Input.integer(body.get("subjectId"),
                "Pick the first subject you will teach.");

        dao.becomeTutor(studentId, doc, subjectId,
                TeachingRules.level(body), TeachingRules.grade(body));

        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of(
                "studentId", studentId,
                "role", "TUTOR",
                "badgeLevel", "BRONZE",
                "message", "You are a tutor now. Your badge starts at Bronze "
                         + "and goes up as you teach more hours."));
    }

    /** POST /api/roles/105/skills — another subject this tutor can teach. */
    @PostMapping("/{studentId}/skills")
    public Map<String, Object> addSkill(@PathVariable int studentId,
                                        @RequestBody Map<String, Object> body)
            throws SQLException {
        int subjectId = TeachingRules.addSkill(dao, studentId, body);
        return Map.of("added", true, "subjectId", subjectId,
                      "message", "Subject added.");
    }

    /** POST /api/roles/105/slots — publish free hours. */
    @PostMapping("/{studentId}/slots")
    public Map<String, Object> addSlot(@PathVariable int studentId,
                                       @RequestBody Map<String, Object> body)
            throws SQLException {
        return TeachingRules.addSlot(dao, studentId, body);
    }

    /**
     * POST /api/roles/105/tutee — become a learner.
     *
     * <p>Body: needTier, and optionally timeBands.
     */
    @PostMapping("/{studentId}/tutee")
    public ResponseEntity<Map<String, Object>> becomeTutee(
            @PathVariable int studentId,
            @RequestBody Map<String, Object> body) throws SQLException {

        StudentLookup.requireExists(studentId);
        if (dao.roleOf(studentId).isTutee()) {
            throw new IllegalArgumentException("You are already a learner.");
        }

        String tier = Input.text(body.get("needTier")) == null ? "BASIC"
                : Input.oneOf(body.get("needTier"),
                        "Choose basic, intermediate or advanced.",
                        "BASIC", "INTERMEDIATE", "ADVANCED");

        List<String> bands = new ArrayList<>();
        if (body.get("timeBands") instanceof List<?> list) {
            for (Object o : list) {
                String b = Input.oneOf(o, "Choose morning, afternoon, evening or night.",
                        "MORNING", "AFTERNOON", "EVENING", "NIGHT");
                if (!bands.contains(b)) bands.add(b);
            }
        }

        dao.becomeTutee(studentId, tier, bands);

        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of(
                "studentId", studentId,
                "role", "TUTEE",
                "needTier", tier,
                "message", "You are a learner now. You can book sessions."));
    }
}
