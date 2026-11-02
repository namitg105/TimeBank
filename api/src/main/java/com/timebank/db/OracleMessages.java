package com.timebank.db;

import java.sql.SQLException;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Turns an Oracle error into one sentence a student can act on.
 *
 * <p>WHY BY CONSTRAINT NAME
 * Oracle reports the error NUMBER (ORA-00001 "unique constraint") and the
 * constraint NAME that fired (UQ_STUDENT_EMAIL). The number alone only
 * says "something was a duplicate"; the name says WHAT was, so each
 * named constraint in 01_ddl.sql gets its own sentence here.
 *
 * <p>The raw Oracle text is never lost: GlobalExceptionHandler prints it
 * in the API window, which is where the examiner looks for it.
 */
final class OracleMessages {

    private OracleMessages() { }

    /** ORA-00001 unique / primary key, ORA-02291 parent missing, ORA-02290 check. */
    private static final Map<String, String> BY_CONSTRAINT = Map.ofEntries(
        // ---- unique and primary keys (ORA-00001)
        Map.entry("UQ_STUDENT_REG",   "That registration number is already registered. Sign in instead."),
        Map.entry("UQ_STUDENT_EMAIL", "That email address is already used by another student."),
        Map.entry("PK_STUDENT_PHONE", "That phone number is already on your list."),
        Map.entry("PK_TUTOR",         "You are already a tutor."),
        Map.entry("PK_TUTEE",         "You are already a learner."),
        Map.entry("PK_TUTOR_SKILL",   "You already teach that subject."),
        Map.entry("PK_TUTEE_PREF",    "That preferred time is already saved."),
        Map.entry("PK_FEEDBACK",      "A review for this session has already been left."),
        Map.entry("UQ_SESSION_CODE",  "Please try booking again."),
        // ---- parent row missing (ORA-02291)
        Map.entry("FK_STUDENT_DEPT",  "That department does not exist. Pick one from the list."),
        Map.entry("FK_PHONE_STUDENT", "That student does not exist."),
        Map.entry("FK_TUTOR_STUDENT", "That student does not exist."),
        Map.entry("FK_TUTEE_STUDENT", "That student does not exist."),
        Map.entry("FK_SKILL_TUTOR",   "You need to be a tutor before adding subjects you teach."),
        Map.entry("FK_SKILL_SUBJECT", "That subject does not exist. Pick one from the list."),
        Map.entry("FK_SLOT_TUTOR",    "You need to be a tutor before adding free hours."),
        Map.entry("FK_PREF_TUTEE",    "You need to be a learner before saving preferred times."),
        Map.entry("FK_BK_TUTEE",      "The learner has not joined as a learner yet."),
        Map.entry("FK_BK_SKILL",      "That tutor does not teach the chosen subject."),
        Map.entry("FK_BK_SLOT",       "That free hour does not exist. Pick one from the list."),
        Map.entry("FK_TXN_STUDENT",   "That student does not exist."),
        Map.entry("FK_DP_ADMIN",      "That administrator does not exist. Pick a name from the list."),
        Map.entry("FK_DP_BOOKING",    "That session does not exist."),
        Map.entry("FK_FB_BOOKING",    "That session does not exist."),
        // ---- check constraints (ORA-02290)
        Map.entry("CHK_PHONE_DIGITS", "A phone number must be exactly 10 digits."),
        Map.entry("CHK_STU_EMAIL",    "That email address does not look right."),
        Map.entry("CHK_SLOT_DAY",     "Pick a day from Monday to Sunday."),
        Map.entry("CHK_SLOT_HRS",     "Free hours must be between 00:00 and 24:00."),
        Map.entry("CHK_SLOT_ORDER",   "Free hours must end after they start."),
        Map.entry("CHK_BK_DURATION",  "A session can last 0.5, 1, 1.5 or 2 hours."),
        Map.entry("CHK_BK_MODE",      "Choose in person or online."),
        Map.entry("CHK_BK_NOT_SELF",  "You cannot book a session with yourself."),
        Map.entry("CHK_TXN_SIGN",     "A grant must add credits and a penalty must take them away."),
        Map.entry("CHK_TXN_NONZERO",  "The amount cannot be zero."),
        Map.entry("CHK_DP_RESOLVED",  "Write a short note explaining the ruling."),
        Map.entry("CHK_FB_RATING",    "A rating must be between 1 and 5."),
        Map.entry("CHK_NEED_TIER",    "Choose basic, intermediate or advanced."),
        Map.entry("CHK_COMPETENCY",   "Choose beginner, proficient or expert."),
        Map.entry("CHK_GRADE_PROOF",  "Choose a grade of S, A, B or C.")
    );

    /** ORA-12899 names the column; these are the ones a form can overfill. */
    private static final Map<String, String> FIELD = Map.ofEntries(
        Map.entry("REG_NO", "Registration number"),
        Map.entry("FIRST_NAME", "First name"),
        Map.entry("LAST_NAME", "Last name"),
        Map.entry("EMAIL", "Email"),
        Map.entry("CITY", "Home city"),
        Map.entry("BLOCK", "Block"),
        Map.entry("ROOM_NO", "Room"),
        Map.entry("VENUE", "Room"),
        Map.entry("REMARKS", "Note"),
        Map.entry("RESOLUTION_NOTE", "Ruling note"),
        Map.entry("REASON", "Reason"),
        Map.entry("VERIFICATION_DOC_NO", "Verification document number")
    );

    private static final Pattern CONSTRAINT = Pattern.compile("\\(\\w+\\.(\\w+)\\)");
    private static final Pattern TOO_LONG = Pattern.compile(
            "\"\\w+\"\\.\"\\w+\"\\.\"(\\w+)\" \\(actual: \\d+, maximum: (\\d+)\\)");

    static String explain(SQLException e) {
        int code = e.getErrorCode();
        String raw = e.getMessage() == null ? "" : e.getMessage();

        // Our own RAISE_APPLICATION_ERROR messages are already sentences.
        if (code >= 20000 && code <= 20999) {
            int nl = raw.indexOf('\n');
            String first = nl > 0 ? raw.substring(0, nl) : raw;
            return first.replaceFirst("^ORA-\\d+:\\s*", "").trim();
        }

        if (code == 1 || code == 2290 || code == 2291) {
            Matcher m = CONSTRAINT.matcher(raw);
            if (m.find() && BY_CONSTRAINT.containsKey(m.group(1))) {
                return BY_CONSTRAINT.get(m.group(1));
            }
        }

        if (code == 12899) {
            Matcher m = TOO_LONG.matcher(raw);
            if (m.find()) {
                String field = FIELD.getOrDefault(m.group(1), "One of the entries");
                return field + " is too long. Use at most " + m.group(2) + " characters.";
            }
        }

        return switch (code) {
            case 1     -> "That already exists.";
            case 1400  -> "Something required was left empty.";
            case 1438  -> "That number is too large.";
            case 2290  -> "One of the values is not allowed. Check the form and try again.";
            case 2291  -> "Something you picked no longer exists. Reload and try again.";
            case 2292  -> "This cannot be removed because other records depend on it.";
            case 12899 -> "One of the entries is too long.";
            case 60    -> "Two requests clashed. Please try again.";
            default    -> "The database could not finish that. Please try again.";
        };
    }
}
