package com.timebank.api.web;

import com.timebank.dao.BookingDao;
import com.timebank.dao.RoleDao;
import com.timebank.dao.StudentLookup;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.sql.SQLException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Booking a session while picking your side of it.
 *
 * <p>WHY THIS ENDPOINT EXISTS
 * A student does not think "first enrol me in the TUTEE subclass, then
 * create a booking". They think "I want help with Databases on Monday".
 * This endpoint takes that intent and does whatever the schema requires
 * to make it legal:
 *
 * <ol>
 *   <li>work out which side of the session this student is on;</li>
 *   <li>if they are not yet in that subclass table, enrol them;</li>
 *   <li>if they are teaching a subject they have never registered,
 *       record the skill;</li>
 *   <li>book the session through PKG_TIMEBANK.</li>
 * </ol>
 *
 * <p>THE ER POINT, WHICH IS THE WHOLE REASON THIS IS INTERESTING
 * Nothing here <em>removes</em> a role. Choosing to teach does not stop
 * you learning, because the specialization is <b>overlapping</b> — so
 * the same person can end up in TUTOR and TUTEE, and the Students
 * screen will show them as BOTH. And a student who never books anything
 * stays in neither table, because it is also <b>partial</b>.
 *
 * <p>If the specialization were disjoint this endpoint could not exist:
 * picking a side would have to un-pick the other one.
 */
@RestController
@RequestMapping("/api/bookings")
public class GuidedBookingController {

    private final RoleDao    roles    = new RoleDao();
    private final BookingDao bookings = new BookingDao();

    /**
     * POST /api/bookings/guided
     *
     * <pre>
     * {
     *   "studentId":     1003,
     *   "intent":        "LEARN",        // or "TEACH"
     *   "counterpartId": 101,            // the other person
     *   "subjectId":     101,
     *   "slotNo":        1,
     *   "schedDate":     "2026-11-02",
     *   "startTime":     16,
     *   "durationHours": 1.0,
     *   "mode":          "OFFLINE",
     *   "venue":         "SJT 512"
     * }
     * </pre>
     */
    @PostMapping("/guided")
    public ResponseEntity<Map<String, Object>> guided(
            @RequestBody Map<String, Object> body) throws SQLException {

        // Either field may be a registration number or a bare id -- the
        // registration number is the one people actually know.
        Integer studentId     = StudentLookup.resolve(
                                    str(body.get("studentId"), null));
        Integer counterpartId = StudentLookup.resolve(
                                    str(body.get("counterpartId"), null));
        Integer subjectId     = intOf(body.get("subjectId"), "subjectId");
        Integer slotNo        = intOf(body.get("slotNo"),    "slotNo");

        String intent = str(body.get("intent"), "LEARN").toUpperCase();
        if (!intent.equals("LEARN") && !intent.equals("TEACH")) {
            throw new IllegalArgumentException(
                    "intent must be LEARN or TEACH.");
        }

        if (studentId.equals(counterpartId)) {
            throw new IllegalArgumentException(
                    "You cannot book a session with yourself.");
        }

        // Who sits on which side of the session.
        int tuteeId = intent.equals("LEARN") ? studentId : counterpartId;
        int tutorId = intent.equals("LEARN") ? counterpartId : studentId;

        List<String> steps = new ArrayList<>();

        // When learning, the other person must already teach this subject.
        // Checked here so the student reads a sentence, not ORA-02291.
        if (intent.equals("LEARN")) {
            String who = str(body.get("counterpartId"), "");
            if (!roles.roleOf(tutorId).isTutor()) {
                throw new IllegalArgumentException(
                        who + " is not teaching any subjects yet.");
            }
            if (!roles.teaches(tutorId, subjectId)) {
                throw new IllegalArgumentException(
                        who + " does not teach that subject.");
            }
        }

        RoleDao.RoleState before = roles.roleOf(studentId);
        steps.add("Student " + studentId + " was: " + before.label());

        // -------------------------------------------------------------
        //  Enrol into whichever subclass this intent needs.
        //  Nothing is removed -- that is what "overlapping" means.
        // -------------------------------------------------------------
        if (intent.equals("LEARN") && !before.isTutee()) {
            String tier = str(body.get("needTier"), "BASIC").toUpperCase();
            requireOneOf(tier, "needTier", "BASIC", "INTERMEDIATE", "ADVANCED");

            roles.becomeTutee(studentId, tier, bands(body.get("timeBands")));
            steps.add("Enrolled as a MENTEE (TUTEE row created, tier " + tier + ")");
        }

        if (intent.equals("TEACH")) {
            String competency = str(body.get("competency"), "PROFICIENT")
                                    .toUpperCase();
            String grade = str(body.get("grade"), "A").toUpperCase();

            requireOneOf(competency, "competency",
                         "BEGINNER", "PROFICIENT", "EXPERT");
            requireOneOf(grade, "grade", "S", "A", "B", "C");

            if (!before.isTutor()) {
                String doc = str(body.get("verificationDocNo"),
                                 "SELF-" + studentId);
                roles.becomeTutor(studentId, doc, subjectId, competency, grade);
                steps.add("Enrolled as a MENTOR (TUTOR row created, badge BRONZE, "
                        + "plus a TUTOR_SKILL row for subject " + subjectId + ")");
            } else if (!roles.teaches(studentId, subjectId)) {
                // Already a tutor, but not of this subject: record the
                // skill, otherwise FK_BK_SKILL rejects the booking.
                roles.addSkill(studentId, subjectId, competency, grade);
                steps.add("Added subject " + subjectId + " to what this mentor "
                        + "teaches (TUTOR_SKILL row created)");
            }

            // The learner must be in TUTEE too, or FK_BK_TUTEE rejects
            // the booking. Being taught makes them a mentee, so enrol them
            // the same way a student who books to learn is enrolled.
            if (!roles.roleOf(tuteeId).isTutee()) {
                roles.becomeTutee(tuteeId, "BASIC", List.of());
                steps.add("Enrolled student " + tuteeId
                        + " as a MENTEE (TUTEE row created, tier BASIC)");
            }
        }

        RoleDao.RoleState after = roles.roleOf(studentId);
        if (!before.label().equals(after.label())) {
            steps.add("Student " + studentId + " is now: " + after.label());
        }

        // -------------------------------------------------------------
        //  Book it. Every rule that matters lives in the package and in
        //  the triggers, so nothing is re-checked here.
        // -------------------------------------------------------------
        var result = bookings.book(
                tuteeId, tutorId, subjectId, slotNo,
                LocalDate.parse(str(body.get("schedDate"), null)),
                dbl(body.get("startTime"), "startTime"),
                dbl(body.get("durationHours"), "durationHours"),
                str(body.get("mode"), "ONLINE").toUpperCase(),
                str(body.get("venue"), null));

        steps.add("Booking " + result.bookingId()
                + " created and the credits moved into escrow");

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("bookingId",   result.bookingId());
        out.put("sessionCode", result.sessionCode());
        out.put("tuteeId",     tuteeId);
        out.put("tutorId",     tutorId);
        out.put("roleBefore",  before.label());
        out.put("roleAfter",   after.label());
        out.put("steps",       steps);
        out.put("message", intent.equals("LEARN")
                ? "Booked as the learner. Keep the session code -- the tutor "
                + "has to type it in to prove you turned up."
                : "Booked as the teacher. The tutee has a session code; "
                + "ask for it at the start of the session.");

        return ResponseEntity.status(HttpStatus.CREATED).body(out);
    }

    // -----------------------------------------------------------------

    @SuppressWarnings("unchecked")
    private static List<String> bands(Object raw) {
        if (!(raw instanceof List<?> list)) {
            return List.of();
        }
        List<String> out = new ArrayList<>();
        for (Object o : list) {
            String b = String.valueOf(o).trim().toUpperCase();
            requireOneOf(b, "timeBand",
                         "MORNING", "AFTERNOON", "EVENING", "NIGHT");
            out.add(b);
        }
        return out;
    }

    private static String str(Object o, String fallback) {
        if (o == null) {
            return fallback;
        }
        String s = String.valueOf(o).trim();
        return s.isEmpty() ? fallback : s;
    }

    private static Integer intOf(Object o, String field) {
        if (o instanceof Number n) {
            return n.intValue();
        }
        try {
            return Integer.valueOf(String.valueOf(o).trim());
        } catch (Exception e) {
            throw new IllegalArgumentException(field + " is required.");
        }
    }

    private static double dbl(Object o, String field) {
        if (o instanceof Number n) {
            return n.doubleValue();
        }
        try {
            return Double.parseDouble(String.valueOf(o).trim());
        } catch (Exception e) {
            throw new IllegalArgumentException(field + " is required.");
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
