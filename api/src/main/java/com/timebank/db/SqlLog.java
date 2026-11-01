package com.timebank.db;

import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

/**
 * Prints every statement the application sends to Oracle, to the console.
 *
 * <p>WHY THIS EXISTS
 * A screen that simply shows data proves nothing on its own — the rows
 * could have been typed into the source. This class makes the database
 * work visible: click a button in the app and the exact SQL that ran,
 * the values bound into it, the number of rows it touched and how long
 * Oracle took all appear in this terminal, in real time.
 *
 * <p>WHAT TO POINT AT WHEN DEMONSTRATING
 * <ul>
 *   <li>The {@code ?} marks. Nothing is ever concatenated into the SQL,
 *       so the statement sent to Oracle is fixed text and the values
 *       travel separately. That is what makes SQL injection impossible,
 *       and it lets Oracle reuse one parsed plan for every value.</li>
 *   <li>The BIND lines. Those are the values that filled the {@code ?}
 *       marks on this particular click.</li>
 *   <li>The timing. Sub-millisecond reads are the indexes working.</li>
 * </ul>
 *
 * <p>This is deliberately plain {@code System.out} rather than a logging
 * framework: it has to be readable over someone's shoulder on a
 * projector, not parsed by a log aggregator.
 */
public final class SqlLog {

    private static final DateTimeFormatter CLOCK =
            DateTimeFormatter.ofPattern("HH:mm:ss");

    private static final String RULE =
            "--------------------------------------------------"
          + "--------------------------";

    /** Set false to silence the trace (for example when load testing). */
    public static boolean enabled = true;

    private SqlLog() { }

    /**
     * Announces a statement about to run.
     *
     * @param label  where it came from, e.g. {@code "StudentDao.search"}
     * @param sql    the statement itself, {@code ?} marks and all
     * @param binds  the values being bound, in order
     * @return the start time in nanoseconds, to hand back to
     *         {@link #rows} or {@link #changed}
     */
    public static long q(String label, String sql, Object... binds) {
        if (!enabled) {
            return System.nanoTime();
        }

        StringBuilder out = new StringBuilder();
        out.append('\n').append(RULE).append('\n');
        out.append("  ").append(LocalTime.now().format(CLOCK))
           .append("   ").append(label).append('\n');
        out.append(RULE).append('\n');

        for (String line : sql.strip().split("\n")) {
            out.append("  ").append(line).append('\n');
        }

        if (binds != null && binds.length > 0) {
            out.append('\n');
            for (int i = 0; i < binds.length; i++) {
                out.append(String.format("  bind %d  =  %s%n",
                        i + 1, render(binds[i])));
            }
        }

        System.out.print(out);
        return System.nanoTime();
    }

    /** Reports the outcome of a SELECT. */
    public static void rows(int count, long startNanos) {
        finish(count + (count == 1 ? " row read" : " rows read"), startNanos);
    }

    /** Reports the outcome of an INSERT, UPDATE or DELETE. */
    public static void changed(int count, long startNanos) {
        finish(count + (count == 1 ? " row changed" : " rows changed"),
               startNanos);
    }

    /**
     * Shows the statements that run INSIDE a PL/SQL package.
     *
     * <p>When the application calls a stored procedure, the only thing
     * that crosses the JDBC connection is the {@code BEGIN pkg...; END;}
     * call. The INSERTs and UPDATEs it performs are compiled into the
     * database and never travel back, so a wire trace alone makes it
     * look as though nothing was written.
     *
     * <p>This prints them so the work is visible. It is a quotation from
     * the package source, clearly labelled as such — not something the
     * application sent.
     */
    public static void inside(String procedure, String sql) {
        if (!enabled) {
            return;
        }
        StringBuilder out = new StringBuilder();
        out.append("\n  Inside ").append(procedure).append(":\n\n");
        for (String line : sql.strip().split("\n")) {
            out.append("      ").append(line).append('\n');
        }
        System.out.print(out);
    }

    /** A one-line aside, used when a read-back could not be done. */
    public static void note(String text) {
        if (enabled) {
            System.out.println("    " + text);
        }
    }

    /** Reports a PL/SQL call, which has no row count of its own. */
    public static void called(String what, long startNanos) {
        finish(what, startNanos);
    }

    /**
     * Reports a statement Oracle refused.
     *
     * <p>Worth showing rather than hiding: an ORA-20001 here is a trigger
     * doing its job, and the refusal is as much a result as a row count.
     */
    public static void failed(String message, long startNanos) {
        finish("REFUSED BY ORACLE -> " + firstLine(message), startNanos);
    }

    private static void finish(String outcome, long startNanos) {
        if (!enabled) {
            return;
        }
        double ms = (System.nanoTime() - startNanos) / 1_000_000.0;
        System.out.printf("%n  ->  %s in %.1f ms%n%s%n",
                outcome, ms, RULE);
    }

    /**
     * Prints the rows a statement actually left behind.
     *
     * <p>A row count says "3 rows changed". This says WHICH rows and
     * what is now in them, which is the thing worth seeing: the new
     * student and the credit row created alongside her, the booking
     * whose status just moved, the ledger entry that recorded it.
     *
     * <p>Called after the write has committed, so what prints is what
     * another session would see — not an uncommitted guess.
     */
    public static void after(String title, ResultSet rs) throws SQLException {
        if (!enabled) {
            return;
        }

        ResultSetMetaData meta = rs.getMetaData();
        int cols = meta.getColumnCount();

        List<String> headers = new ArrayList<>();
        for (int i = 1; i <= cols; i++) {
            headers.add(meta.getColumnLabel(i));
        }

        List<List<String>> rows = new ArrayList<>();
        while (rs.next()) {
            List<String> row = new ArrayList<>();
            for (int i = 1; i <= cols; i++) {
                Object v = rs.getObject(i);
                row.add(v == null ? "-" : String.valueOf(v));
            }
            rows.add(row);
        }

        StringBuilder out = new StringBuilder();
        out.append("\n  ").append(title).append('\n');

        if (rows.isEmpty()) {
            out.append("    (no rows)\n");
            System.out.print(out);
            return;
        }

        int[] width = new int[cols];
        for (int i = 0; i < cols; i++) {
            width[i] = headers.get(i).length();
            for (List<String> row : rows) {
                width[i] = Math.max(width[i], Math.min(row.get(i).length(), 38));
            }
        }

        out.append("    ");
        for (int i = 0; i < cols; i++) {
            out.append(pad(headers.get(i), width[i])).append("  ");
        }
        out.append('\n').append("    ");
        for (int i = 0; i < cols; i++) {
            out.append("-".repeat(width[i])).append("  ");
        }
        out.append('\n');

        for (List<String> row : rows) {
            out.append("    ");
            for (int i = 0; i < cols; i++) {
                out.append(pad(row.get(i), width[i])).append("  ");
            }
            out.append('\n');
        }

        System.out.print(out);
    }

    private static String pad(String s, int w) {
        String t = s.length() > 38 ? s.substring(0, 35) + "..." : s;
        return t.length() >= w ? t : t + " ".repeat(w - t.length());
    }

    private static String render(Object v) {
        if (v == null) {
            return "NULL";
        }
        if (v instanceof String s) {
            return "'" + s + "'";
        }
        return v.toString();
    }

    private static String firstLine(String s) {
        if (s == null) {
            return "(no message)";
        }
        int nl = s.indexOf('\n');
        return nl > 0 ? s.substring(0, nl) : s;
    }
}
