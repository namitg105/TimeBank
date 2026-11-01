package com.timebank.api.web;

import com.timebank.dao.RoleDao;
import com.timebank.dao.SkillsDao;
import org.springframework.web.bind.annotation.*;

import java.sql.SQLException;
import java.util.List;
import java.util.Map;

/**
 * Skills and availability, over HTTP.
 *
 * <p>MEMBER 2 — SUBJECT, TUTOR_SKILL, SLOT.
 */
@RestController
@RequestMapping("/api/skills")
public class SkillsController {

    private final SkillsDao skills = new SkillsDao();
    private final RoleDao   roles  = new RoleDao();

    /** GET /api/skills/subjects — the catalogue. */
    @GetMapping("/subjects")
    public List<RoleDao.Subject> subjects() throws SQLException {
        return roles.subjects();
    }

    /**
     * GET /api/skills/matrix            — everybody
     * GET /api/skills/matrix?tutorId=101 — one tutor
     */
    @GetMapping("/matrix")
    public List<Map<String, Object>> matrix(
            @RequestParam(required = false) Integer tutorId)
            throws SQLException {
        return skills.skillMatrix(tutorId);
    }

    /** GET /api/skills/gaps — subjects nobody has registered to teach. */
    @GetMapping("/gaps")
    public List<Map<String, Object>> gaps() throws SQLException {
        return skills.subjectsWithNoTutor();
    }

    /** GET /api/skills/capacity — tutors per subject. */
    @GetMapping("/capacity")
    public List<Map<String, Object>> capacity() throws SQLException {
        return skills.capacity();
    }

    /** GET /api/skills/slots/101 — one tutor's published availability. */
    @GetMapping("/slots/{tutorId}")
    public List<Map<String, Object>> slots(@PathVariable int tutorId)
            throws SQLException {
        return skills.slotsOf(tutorId);
    }

    /** POST /api/skills/slots/101 — publish a slot. */
    @PostMapping("/slots/{tutorId}")
    public Map<String, Object> addSlot(@PathVariable int tutorId,
                                       @RequestBody Map<String, Object> body)
            throws SQLException {

        String day = str(body.get("dayOfWeek"), "").toUpperCase();
        oneOf(day, "dayOfWeek", "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN");

        int start = intOf(body.get("startTime"), "startTime");
        int end   = intOf(body.get("endTime"), "endTime");
        if (end <= start) {
            throw new IllegalArgumentException(
                    "The slot has to end after it starts — CHK_SLOT_ORDER "
                  + "would refuse it anyway.");
        }

        roles.addSlot(tutorId, day, start, end);
        return Map.of("added", true, "dayOfWeek", day,
                      "startTime", start, "endTime", end);
    }

    /** DELETE /api/skills/slots/101/2 — withdraw a slot. */
    @DeleteMapping("/slots/{tutorId}/{slotNo}")
    public Map<String, Object> removeSlot(@PathVariable int tutorId,
                                          @PathVariable int slotNo)
            throws SQLException {
        int n = skills.removeSlot(tutorId, slotNo);
        return Map.of(
                "removed", n,
                "message", n > 0
                    ? "Slot withdrawn."
                    : "Not removed — either there is no such slot, or a "
                    + "session is already booked against it and FK_BK_SLOT "
                    + "protects it.");
    }

    /** POST /api/skills/101 — register a subject this tutor can teach. */
    @PostMapping("/{tutorId}")
    public Map<String, Object> addSkill(@PathVariable int tutorId,
                                        @RequestBody Map<String, Object> body)
            throws SQLException {

        int subjectId = intOf(body.get("subjectId"), "subjectId");
        String level  = str(body.get("competency"), "PROFICIENT").toUpperCase();
        String grade  = str(body.get("grade"), "A").toUpperCase();

        oneOf(level, "competency", "BEGINNER", "PROFICIENT", "EXPERT");
        oneOf(grade, "grade", "S", "A", "B", "C");

        roles.addSkill(tutorId, subjectId, level, grade);
        return Map.of("added", true, "subjectId", subjectId);
    }

    /** PUT /api/skills/101/104 — change a competency level. */
    @PutMapping("/{tutorId}/{subjectId}")
    public Map<String, Object> setCompetency(
            @PathVariable int tutorId,
            @PathVariable int subjectId,
            @RequestBody Map<String, Object> body) throws SQLException {

        String level = str(body.get("competency"), "PROFICIENT").toUpperCase();
        String grade = str(body.get("grade"), "A").toUpperCase();

        oneOf(level, "competency", "BEGINNER", "PROFICIENT", "EXPERT");
        oneOf(grade, "grade", "S", "A", "B", "C");

        int n = skills.setCompetency(tutorId, subjectId, level, grade);
        return Map.of("changed", n);
    }

    // -----------------------------------------------------------------

    private static String str(Object o, String fallback) {
        if (o == null) {
            return fallback;
        }
        String s = String.valueOf(o).trim();
        return s.isEmpty() ? fallback : s;
    }

    private static int intOf(Object o, String field) {
        if (o instanceof Number n) {
            return n.intValue();
        }
        try {
            return Integer.parseInt(String.valueOf(o).trim());
        } catch (Exception e) {
            throw new IllegalArgumentException(field + " is required.");
        }
    }

    private static void oneOf(String v, String field, String... allowed) {
        for (String a : allowed) {
            if (a.equals(v)) {
                return;
            }
        }
        throw new IllegalArgumentException(
                field + " must be one of " + String.join(", ", allowed)
              + " (got " + v + ").");
    }
}
