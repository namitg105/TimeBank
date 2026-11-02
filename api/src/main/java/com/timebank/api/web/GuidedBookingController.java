package com.timebank.api.web;

import com.timebank.dao.BookingDao;
import com.timebank.dao.RoleDao;
import com.timebank.dao.StudentLookup;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.sql.SQLException;
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

        // -------------------------------------------------------------
        //  1. Check EVERYTHING first. Nothing below this block may fail
        //     on bad input, so a refused booking never leaves a new role
        //     behind.
        // -------------------------------------------------------------
        // Either field may be a registration number or a bare id -- the
        // registration number is the one people actually know.
        int studentId = StudentLookup.resolve(Input.text(body.get("studentId")));
        String who = Input.required(body.get("counterpartId"),
                "Enter the other person's registration number.");
        int counterpartId = StudentLookup.resolve(who);

        String intent = Input.text(body.get("intent")) == null ? "LEARN"
                : Input.oneOf(body.get("intent"),
                        "Choose whether you are learning or teaching.", "LEARN", "TEACH");

        if (studentId == counterpartId) {
            throw new IllegalArgumentException("You cannot book a session with yourself.");
        }

        StudentLookup.requireActive(studentId,
                "Your account has been deactivated, so you cannot book.");
        StudentLookup.requireActive(counterpartId,
                who + "'s account has been deactivated, so they cannot be booked.");

        SessionDetails d = SessionDetails.from(body);

        // Who sits on which side of the session.
        int tuteeId = intent.equals("LEARN") ? studentId : counterpartId;
        int tutorId = intent.equals("LEARN") ? counterpartId : studentId;

        // When learning, the other person must already teach this subject.
        if (intent.equals("LEARN")) {
            if (!roles.roleOf(tutorId).isTutor()) {
                throw new IllegalArgumentException(
                        who + " is not teaching any subjects yet.");
            }
            if (!roles.teaches(tutorId, d.subjectId())) {
                throw new IllegalArgumentException(
                        who + " does not teach that subject.");
            }
        }

        String level = TeachingRules.level(body);
        String grade = TeachingRules.grade(body);

        // -------------------------------------------------------------
        //  2. Enrol into whichever subclass this intent needs.
        //     Nothing is removed -- that is what "overlapping" means.
        // -------------------------------------------------------------
        List<String> steps = new ArrayList<>();
        RoleDao.RoleState before = roles.roleOf(studentId);
        steps.add("Student " + studentId + " was: " + before.label());

        if (intent.equals("LEARN") && !before.isTutee()) {
            roles.becomeTutee(studentId, "BASIC", List.of());
            steps.add("Enrolled as a learner (TUTEE row created, tier BASIC)");
        }

        if (intent.equals("TEACH")) {
            if (!before.isTutor()) {
                roles.becomeTutor(studentId, "SELF-" + studentId,
                        d.subjectId(), level, grade);
                steps.add("Enrolled as a tutor (TUTOR row created, badge BRONZE, "
                        + "plus a TUTOR_SKILL row for subject " + d.subjectId() + ")");
            } else if (!roles.teaches(studentId, d.subjectId())) {
                // Already a tutor, but not of this subject: record the
                // skill, otherwise FK_BK_SKILL rejects the booking.
                roles.addSkill(studentId, d.subjectId(), level, grade);
                steps.add("Added subject " + d.subjectId()
                        + " to what this tutor teaches (TUTOR_SKILL row created)");
            }

            // The learner must be in TUTEE too, or FK_BK_TUTEE rejects
            // the booking. Being taught makes them a learner.
            if (!roles.roleOf(tuteeId).isTutee()) {
                roles.becomeTutee(tuteeId, "BASIC", List.of());
                steps.add("Enrolled student " + tuteeId
                        + " as a learner (TUTEE row created, tier BASIC)");
            }
        }

        RoleDao.RoleState after = roles.roleOf(studentId);
        if (!before.label().equals(after.label())) {
            steps.add("Student " + studentId + " is now: " + after.label());
        }

        // -------------------------------------------------------------
        //  3. Book it. The free hour, weekday, credits, clashes and the
        //     weekly limit are checked inside PKG_TIMEBANK under a lock.
        // -------------------------------------------------------------
        var result = bookings.book(tuteeId, tutorId, d.subjectId(), d.slotNo(),
                d.date(), d.startTime(), d.durationHours(), d.mode(), d.venue());

        steps.add("Booking " + result.bookingId()
                + " created and the credits set aside (HOLD)");

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("bookingId",   result.bookingId());
        // A tutor may create a booking for a learner, but must not learn
        // the code in doing so. The learner receives it from their own
        // Sessions list, where BookingDao selects it only for that side.
        if (studentId == tuteeId) {
            out.put("sessionCode", result.sessionCode());
        }
        out.put("tuteeId",     tuteeId);
        out.put("tutorId",     tutorId);
        out.put("roleBefore",  before.label());
        out.put("roleAfter",   after.label());
        out.put("steps",       steps);
        out.put("message", intent.equals("LEARN")
                ? "Booked. Keep the session code: you read it to the tutor "
                + "when you meet."
                : "Booked. The learner has a session code; ask for it when "
                + "you meet.");

        return ResponseEntity.status(HttpStatus.CREATED).body(out);
    }
}
