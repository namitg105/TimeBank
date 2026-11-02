package com.timebank.api.web;

import com.timebank.dao.RoleDao;
import com.timebank.dao.SkillsDao;
import com.timebank.dao.StudentLookup;
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

    /**
     * GET /api/skills/slots/101  or  /api/skills/slots/25BCE1001
     *
     * <p>Accepts a registration number as well as an id, because that
     * is what a person booking a session actually knows.
     */
    @GetMapping("/slots/{ref}")
    public List<Map<String, Object>> slots(@PathVariable String ref)
            throws SQLException {
        return skills.slotsOf(StudentLookup.resolve(ref));
    }

    /** POST /api/skills/slots/101 — publish free hours. */
    @PostMapping("/slots/{tutorId}")
    public Map<String, Object> addSlot(@PathVariable int tutorId,
                                       @RequestBody Map<String, Object> body)
            throws SQLException {
        return TeachingRules.addSlot(roles, tutorId, body);
    }

    /**
     * DELETE /api/skills/slots/101/2 — withdraw free hours.
     *
     * <p>Only hours nobody has ever booked can go. Every BOOKING row
     * points at its slot through FK_BK_SLOT, finished and cancelled ones
     * included, so removing a slot with history would orphan it.
     */
    @DeleteMapping("/slots/{tutorId}/{slotNo}")
    public Map<String, Object> removeSlot(@PathVariable int tutorId,
                                          @PathVariable int slotNo)
            throws SQLException {
        StudentLookup.requireExists(tutorId);
        boolean exists = skills.slotsOf(tutorId).stream()
                .anyMatch(s -> ((Number) s.get("slotNo")).intValue() == slotNo);
        if (!exists) {
            throw new IllegalArgumentException("Those free hours no longer exist.");
        }

        int n = skills.removeSlot(tutorId, slotNo);
        if (n == 0) {
            throw new IllegalArgumentException(
                    "These hours have sessions on record, past or upcoming, "
                  + "so they stay. You can add new hours instead.");
        }
        return Map.of("removed", n, "message", "Free hours removed.");
    }

    /** POST /api/skills/101 — register a subject this tutor can teach. */
    @PostMapping("/{tutorId}")
    public Map<String, Object> addSkill(@PathVariable int tutorId,
                                        @RequestBody Map<String, Object> body)
            throws SQLException {
        int subjectId = TeachingRules.addSkill(roles, tutorId, body);
        return Map.of("added", true, "subjectId", subjectId,
                      "message", "Subject added.");
    }

    /** PUT /api/skills/101/104 — change a competency level. */
    @PutMapping("/{tutorId}/{subjectId}")
    public Map<String, Object> setCompetency(
            @PathVariable int tutorId,
            @PathVariable int subjectId,
            @RequestBody Map<String, Object> body) throws SQLException {

        TeachingRules.requireTutor(roles, tutorId,
                "You need to be a tutor before changing a subject level.");
        if (!roles.teaches(tutorId, subjectId)) {
            throw new IllegalArgumentException("You do not teach that subject yet.");
        }

        int n = skills.setCompetency(tutorId, subjectId,
                TeachingRules.level(body), TeachingRules.grade(body));
        return Map.of("changed", n, "message", "Level updated.");
    }
}
