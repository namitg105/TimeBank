package com.timebank.api.web;

import com.timebank.dao.RoleDao;
import com.timebank.dao.StudentLookup;

import java.sql.SQLException;
import java.util.Map;

/**
 * The checks for "add a subject I teach" and "add free hours".
 *
 * <p>Both actions are reachable from two controllers (RoleController,
 * used while enrolling, and SkillsController, used by the Subjects
 * screen), so the rules live here once instead of drifting apart.
 */
final class TeachingRules {

    private TeachingRules() { }

    static final String[] LEVELS = {"BEGINNER", "PROFICIENT", "EXPERT"};
    static final String[] GRADES = {"S", "A", "B", "C"};
    static final String[] DAYS   = {"MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"};

    /** Competency level, PROFICIENT when not given. */
    static String level(Map<String, Object> body) {
        return Input.text(body.get("competency")) == null ? "PROFICIENT"
             : Input.oneOf(body.get("competency"),
                           "Choose beginner, proficient or expert.", LEVELS);
    }

    /** Grade proof, A when not given. */
    static String grade(Map<String, Object> body) {
        return Input.text(body.get("grade")) == null ? "A"
             : Input.oneOf(body.get("grade"), "Choose a grade of S, A, B or C.", GRADES);
    }

    static void requireTutor(RoleDao roles, int studentId, String messageIfNot)
            throws SQLException {
        StudentLookup.requireExists(studentId);
        if (!roles.roleOf(studentId).isTutor()) {
            throw new IllegalArgumentException(messageIfNot);
        }
    }

    /** Registers one more subject this tutor teaches. */
    static int addSkill(RoleDao roles, int tutorId, Map<String, Object> body)
            throws SQLException {
        requireTutor(roles, tutorId,
                "You need to be a tutor before adding subjects you teach.");
        int subjectId = Input.integer(body.get("subjectId"), "Pick a subject.");
        String level = level(body);
        String grade = grade(body);

        if (roles.teaches(tutorId, subjectId)) {
            throw new IllegalArgumentException("You already teach that subject.");
        }
        roles.addSkill(tutorId, subjectId, level, grade);
        return subjectId;
    }

    /** Publishes free hours, after checking day, range and order. */
    static Map<String, Object> addSlot(RoleDao roles, int tutorId,
                                       Map<String, Object> body) throws SQLException {
        requireTutor(roles, tutorId, "You need to be a tutor before adding free hours.");

        String day = Input.oneOf(body.get("dayOfWeek"), "Pick a day of the week.", DAYS);
        int start = Input.integer(body.get("startTime"), "Pick a start time.");
        int end   = Input.integer(body.get("endTime"), "Pick an end time.");

        if (start < 0 || end > 24) {
            throw new IllegalArgumentException("Free hours must be between 00:00 and 24:00.");
        }
        if (end <= start) {
            throw new IllegalArgumentException("Free hours must end after they start.");
        }

        roles.addSlot(tutorId, day, start, end);
        return Map.of("added", true, "dayOfWeek", day, "startTime", start, "endTime", end,
                      "message", "Free hours added. People can book you then.");
    }
}
