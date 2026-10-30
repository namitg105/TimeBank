package com.timebank.db;

import java.time.LocalTime;
import java.time.format.DateTimeFormatter;

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
