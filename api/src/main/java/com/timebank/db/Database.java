package com.timebank.db;

import oracle.ucp.jdbc.PoolDataSource;
import oracle.ucp.jdbc.PoolDataSourceFactory;

import java.io.InputStream;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Properties;

/**
 * The single JDBC entry point for the whole application.
 *
 * <p>WHY A CONNECTION POOL?
 * Opening an Oracle connection means a TCP handshake, authentication and
 * session setup — a few hundred milliseconds every time. A screen that
 * opened its own connection would feel sluggish and would fall over under
 * load. The pool opens a handful once at startup and lends them out;
 * {@code close()} on a pooled connection returns it rather than tearing
 * it down.
 *
 * <p>WHY THE THIN DRIVER?
 * {@code jdbc:oracle:thin:@//host:port/service} is pure Java. Nothing has
 * to be installed on the machine beyond the jar itself, which is what
 * makes this project runnable on any teammate's laptop.
 */
public final class Database {

    private static PoolDataSource pool;

    private Database() { }

    /** Builds the pool from db.properties. Call once at startup. */
    public static synchronized void init() throws SQLException {
        if (pool != null) {
            return;
        }

        Properties cfg = new Properties();
        try (InputStream in = Database.class.getClassLoader()
                                  .getResourceAsStream("db.properties")) {
            if (in == null) {
                throw new IllegalStateException(
                    "db.properties not found on the classpath. "
                  + "Copy db.properties.sample and fill in your password.");
            }
            cfg.load(in);
        } catch (Exception e) {
            throw new SQLException("Could not read db.properties", e);
        }

        pool = PoolDataSourceFactory.getPoolDataSource();
        pool.setConnectionFactoryClassName("oracle.jdbc.pool.OracleDataSource");
        pool.setURL(cfg.getProperty("db.url"));
        pool.setUser(cfg.getProperty("db.user"));
        pool.setPassword(cfg.getProperty("db.password"));
        pool.setInitialPoolSize(2);
        pool.setMinPoolSize(2);
        pool.setMaxPoolSize(10);
        pool.setValidateConnectionOnBorrow(true);
    }

    /**
     * Borrows a connection from the pool.
     *
     * <p>Auto-commit is switched OFF deliberately. With it on, every
     * single statement would commit by itself, so a two-statement
     * operation such as "insert the booking, then move the credits"
     * could leave the database half-updated if the second one failed.
     * Every DAO therefore owns its transaction and ends it with an
     * explicit commit or rollback.
     */
    public static Connection get() throws SQLException {
        if (pool == null) {
            init();
        }
        Connection c = pool.getConnection();
        c.setAutoCommit(false);
        return c;
    }

    /**
     * Runs a small SELECT and prints the result, to show what a write
     * actually did.
     *
     * <p>Called after the commit, so the rows printed are the rows any
     * other session would now see. The query is deliberately narrow —
     * the row just touched, not a table scan — because the point is to
     * make one change visible, not to dump data.
     *
     * <p>Failures here are swallowed. This is commentary on work that
     * has already succeeded; it must never turn a completed write into
     * an error the user sees.
     */
    public static void showAfter(String title, String sql, Object... binds) {
        try (Connection c = get();
             PreparedStatement ps = c.prepareStatement(sql)) {

            for (int i = 0; i < binds.length; i++) {
                ps.setObject(i + 1, binds[i]);
            }
            try (ResultSet rs = ps.executeQuery()) {
                SqlLog.after(title, rs);
            }
        } catch (SQLException e) {
            SqlLog.note("(could not read back: " + e.getMessage() + ")");
        }
    }

    /** Rolls back quietly — used in catch blocks where the real error matters more. */
    public static void silentRollback(Connection c) {
        if (c != null) {
            try {
                c.rollback();
            } catch (SQLException ignored) {
                // The original exception is the one worth reporting.
            }
        }
    }

    /**
     * Turns an Oracle error into one sentence a user can act on.
     * The mapping lives in {@link OracleMessages}.
     */
    public static String explain(SQLException e) {
        return OracleMessages.explain(e);
    }
}
