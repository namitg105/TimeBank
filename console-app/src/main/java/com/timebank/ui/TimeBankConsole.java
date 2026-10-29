package com.timebank.ui;

import com.timebank.dao.BookingDao;
import com.timebank.dao.LedgerDao;
import com.timebank.dao.StudentDao;
import com.timebank.db.Database;
import com.timebank.model.Booking;
import com.timebank.model.LedgerEntry;
import com.timebank.model.Student;

import java.math.BigDecimal;
import java.sql.SQLException;
import java.time.LocalDate;
import java.util.List;
import java.util.Scanner;

/**
 * The front end required by the project guidelines: a Java application
 * connected to Oracle over JDBC, demonstrating Insert, Update, Delete,
 * Search and Display.
 *
 * <p>This layer only collects input and prints results. It contains no
 * SQL and no business rules — those live in the DAOs and in the database
 * itself. Keeping the three apart is what lets the same rules apply
 * whether a session is booked from here or from SQL Developer.
 */
public class TimeBankConsole {

    private static final Scanner IN = new Scanner(System.in);

    private static final StudentDao students = new StudentDao();
    private static final BookingDao bookings = new BookingDao();
    private static final LedgerDao  ledger   = new LedgerDao();

    public static void main(String[] args) {
        banner();

        try {
            Database.init();
            System.out.println("Connected to Oracle.\n");
        } catch (SQLException e) {
            System.err.println("Could not connect: " + e.getMessage());
            System.err.println("""

                    Check that:
                      1. Oracle is running        (lsnrctl status)
                      2. db.properties is correct (url, user, password)
                      3. The schema is built      (run the sql/ scripts in order)
                    """);
            return;
        }

        boolean running = true;
        while (running) {
            menu();
            switch (prompt("Choose").trim()) {
                case "1" -> displayStudents();
                case "2" -> searchStudents();
                case "3" -> registerStudent();      // INSERT
                case "4" -> deactivateStudent();    // UPDATE (soft delete)
                case "5" -> removePhone();          // DELETE
                case "6" -> displayBookings();
                case "7" -> bookSession();          // INSERT via PL/SQL
                case "8" -> checkInSession();
                case "9" -> confirmSession();       // UPDATE + escrow release
                case "10" -> cancelSession();
                case "11" -> purgeAbandoned();      // DELETE
                case "12" -> showPassbook();
                case "13" -> postAdjustment();      // INSERT into the ledger
                case "14" -> runAudit();
                case "15" -> showLeaderboard();
                case "16" -> showCollusion();
                case "0"  -> running = false;
                default   -> System.out.println("Not a valid choice.");
            }
        }
        System.out.println("\nGoodbye.");
    }

    // =================================================================
    //  MENU
    // =================================================================

    private static void banner() {
        System.out.println("""
                =====================================================
                  TimeBank : Peer Tutoring Credit Exchange
                  BACSE202 Database Systems  --  Oracle + JDBC
                =====================================================""");
    }

    private static void menu() {
        System.out.println("""

                ---- Students ------------------------------------
                  1  Display all students
                  2  Search students
                  3  Register a student            [INSERT]
                  4  Deactivate an account         [UPDATE]
                  5  Remove a phone number         [DELETE]
                ---- Sessions ------------------------------------
                  6  Display bookings
                  7  Book a session                [INSERT]
                  8  Check in with a session code
                  9  Confirm a session             [UPDATE]
                 10  Cancel a session
                 11  Purge abandoned requests      [DELETE]
                ---- Credits and reports -------------------------
                 12  Passbook for a student
                 13  Post a credit adjustment      [INSERT]
                 14  Closed-economy audit
                 15  Tutor leaderboard
                 16  Collusion report
                  0  Quit""");
    }

    // =================================================================
    //  STUDENTS
    // =================================================================

    private static void displayStudents() {
        run(() -> {
            List<Student> list = students.listAll();
            header("ID    REG NO       NAME                   SCHOOL     BALANCE  ROLE");
            list.forEach(System.out::println);
            System.out.println("\n" + list.size() + " students.");
        });
    }

    private static void searchStudents() {
        String term = prompt("Name or registration number");
        run(() -> {
            List<Student> list = students.search(term);
            if (list.isEmpty()) {
                System.out.println("Nothing matched \"" + term + "\".");
                return;
            }
            header("ID    REG NO       NAME                   SCHOOL     BALANCE  ROLE");
            list.forEach(System.out::println);
        });
    }

    private static void registerStudent() {
        String reg   = prompt("Registration number");
        String first = prompt("First name");
        String last  = prompt("Last name");
        String email = prompt("Email");
        String dob   = prompt("Date of birth (yyyy-mm-dd)");
        int    dept  = promptInt("Department id (1-5)");
        String block = prompt("Hostel block (blank to skip)");
        String room  = prompt("Room number (blank to skip)");
        String city  = prompt("Home city (blank to skip)");

        run(() -> {
            int id = students.register(reg, first, last, email,
                                       LocalDate.parse(dob), dept,
                                       blankToNull(block), blankToNull(room),
                                       blankToNull(city));
            System.out.println("Registered with student id " + id + ".");
            System.out.println("Starter credits: " + students.balanceOf(id));

            String phone = prompt("Phone number (blank to skip)");
            if (!phone.isBlank()) {
                students.addPhone(id, phone);
                System.out.println("Phone added.");
            }
        });
    }

    private static void deactivateStudent() {
        int id = promptInt("Student id to deactivate");
        run(() -> {
            int rows = students.deactivate(id);
            System.out.println(rows == 0
                    ? "No change — either that id does not exist, or the account is already inactive."
                    : "Account closed. Note this is an UPDATE, not a DELETE: "
                      + "their session history and ledger rows have to survive.");
        });
    }

    private static void removePhone() {
        int    id    = promptInt("Student id");
        String phone = prompt("Phone number to remove");
        run(() -> {
            int rows = students.removePhone(id, phone);
            System.out.println(rows == 0 ? "That number was not on record."
                                         : "Removed.");
        });
    }

    // =================================================================
    //  SESSIONS
    // =================================================================

    private static void displayBookings() {
        String filter = prompt("Status filter (blank for all)").trim().toUpperCase();
        run(() -> {
            List<Booking> list = filter.isBlank()
                    ? bookings.listAll()
                    : bookings.byStatus(filter);
            header("ID    DATE       TIME  SUBJECT   TUTEE     -> TUTOR      HOURS STATUS");
            list.forEach(System.out::println);
            System.out.println("\n" + list.size() + " bookings.");
        });
    }

    private static void bookSession() {
        int    tutee   = promptInt("Tutee student id");
        int    tutor   = promptInt("Tutor student id");
        int    subject = promptInt("Subject id (101-110)");
        int    slot    = promptInt("Slot number for that tutor");
        String date    = prompt("Session date (yyyy-mm-dd)");
        double start   = promptDouble("Start time as a decimal hour, e.g. 16.5");
        double hours   = promptDouble("Duration (0.5, 1, 1.5 or 2)");
        String mode    = prompt("ONLINE or OFFLINE");
        String venue   = prompt("Venue or meeting link");

        run(() -> {
            var r = bookings.book(tutee, tutor, subject, slot,
                                  LocalDate.parse(date), start, hours,
                                  mode.toUpperCase(), venue);
            System.out.println("""

                    Booked. Booking id %d.
                    Session code: %s
                      Give this code to the TUTEE only. The tutor types it in at
                      the start of the session, which is what proves the tutee
                      actually turned up.
                    %s credits are now held in escrow; the tutor is paid only
                    once both sides confirm."""
                    .formatted(r.bookingId(), r.sessionCode(), hours));
        });
    }

    private static void checkInSession() {
        int    id   = promptInt("Booking id");
        String code = prompt("Session code from the tutee");
        run(() -> {
            bookings.checkIn(id, code.toUpperCase());
            System.out.println("Checked in. The session can now be confirmed.");
        });
    }

    private static void confirmSession() {
        int    id   = promptInt("Booking id");
        String role = prompt("Confirming as TUTOR or TUTEE");
        run(() -> {
            bookings.confirm(id, role.toUpperCase());
            System.out.println("Confirmation recorded.");
            System.out.println("Credits move only once BOTH sides have confirmed.");
        });
    }

    private static void cancelSession() {
        int    id   = promptInt("Booking id");
        String role = prompt("Cancelling as TUTOR or TUTEE");
        run(() -> {
            bookings.cancel(id, role.toUpperCase());
            System.out.println("""
                    Cancelled.
                      Tutor cancels, or tutee cancels early  -> all credits returned
                      Tutee cancels inside 24 hours          -> split with the tutor""");
        });
    }

    private static void purgeAbandoned() {
        run(() -> {
            int rows = bookings.purgeAbandoned();
            System.out.println(rows + " abandoned request(s) deleted.");
            System.out.println("Only REQUESTED rows can go — anything that reached "
                             + "escrow is referenced by the ledger.");
        });
    }

    // =================================================================
    //  CREDITS AND REPORTS
    // =================================================================

    private static void showPassbook() {
        int id = promptInt("Student id");
        run(() -> {
            List<LedgerEntry> rows = ledger.passbook(id);
            if (rows.isEmpty()) {
                System.out.println("No ledger rows — is that id right?");
                return;
            }
            header("TXN    STUDENT          TYPE      AMOUNT  BALANCE  ORIGIN");
            rows.forEach(System.out::println);
            System.out.println("\nCurrent balance: " + students.balanceOf(id));
            System.out.println("The balance is not stored anywhere — it is summed "
                             + "from these rows every time.");
        });
    }

    private static void postAdjustment() {
        int    id      = promptInt("Student id");
        String type    = prompt("GRANT (credit) or PENALTY (debit)").toUpperCase();
        String amount  = prompt("Amount — positive for GRANT, negative for PENALTY");
        String remarks = prompt("Reason");

        run(() -> {
            long txn = ledger.postAdjustment(id, type, new BigDecimal(amount), remarks);
            System.out.println("Posted as transaction " + txn + ".");
            System.out.println("New balance: " + students.balanceOf(id));
        });
    }

    private static void runAudit() {
        run(() -> {
            LedgerDao.Audit a = ledger.audit();
            System.out.println("""

                    ---- Closed economy audit --------------------------
                      Sum of all balances   : %s
                      Held in escrow        : %s
                      Grants minus penalties: %s
                      Drift                 : %s
                      Verdict               : %s
                    ----------------------------------------------------
                    Every session writes one HOLD and one TRANSFER that cancel
                    out, so the only way the total can change is a new grant or
                    a penalty. Any drift means credits appeared from nowhere."""
                    .formatted(a.balances(), a.escrow(), a.grantsLessPenalties(),
                               a.drift(),
                               a.balanced() ? "BALANCED" : "*** BROKEN ***"));
        });
    }

    private static void showLeaderboard() {
        run(() -> {
            List<String> rows = ledger.leaderboard();
            header("Tutors by hours taught");
            rows.forEach(System.out::println);
        });
    }

    private static void showCollusion() {
        run(() -> {
            List<String> rows = ledger.collusionReport();
            header("Reciprocal pairs");
            if (rows.isEmpty()) {
                System.out.println("None found — no two students are tutoring each other.");
            } else {
                rows.forEach(System.out::println);
                System.out.println("\nThese pairs net out to zero credits but collect "
                                 + "a review each time. Worth a manual look.");
            }
        });
    }

    // =================================================================
    //  helpers
    // =================================================================

    /** Anything that touches the database. */
    @FunctionalInterface
    private interface DbAction {
        void run() throws SQLException;
    }

    /**
     * Runs a database action and turns any Oracle error into a sentence a
     * person can act on. Our own triggers raise codes 20001-20021 with
     * messages already written for humans; Database.explain unwraps them.
     */
    private static void run(DbAction action) {
        try {
            action.run();
        } catch (SQLException e) {
            System.out.println("\n  >> " + Database.explain(e));
        } catch (Exception e) {
            System.out.println("\n  >> Bad input: " + e.getMessage());
        }
    }

    private static void header(String columns) {
        System.out.println();
        System.out.println(columns);
        System.out.println("-".repeat(Math.max(columns.length(), 60)));
    }

    private static String prompt(String label) {
        System.out.print(label + ": ");
        return IN.nextLine();
    }

    private static int promptInt(String label) {
        while (true) {
            try {
                return Integer.parseInt(prompt(label).trim());
            } catch (NumberFormatException e) {
                System.out.println("  that needs to be a whole number.");
            }
        }
    }

    private static double promptDouble(String label) {
        while (true) {
            try {
                return Double.parseDouble(prompt(label).trim());
            } catch (NumberFormatException e) {
                System.out.println("  that needs to be a number, e.g. 1.5");
            }
        }
    }

    private static String blankToNull(String s) {
        return (s == null || s.isBlank()) ? null : s;
    }
}
