package com.timebank.db;

import oracle.ucp.jdbc.PoolDataSource;
import oracle.ucp.jdbc.PoolDataSourceFactory;

import java.io.InputStream;
import java.sql.Connection;
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
     * Turns an Oracle error into something a user can act on.
     * Codes 20001–20021 are the ones our own triggers and package raise
     * with RAISE_APPLICATION_ERROR, so their messages are already
     * written for a human and just need unwrapping.
     */
    public static String explain(SQLException e) {
        int code = e.getErrorCode();

        if (code >= 20001 && code <= 20021) {
            String msg = e.getMessage();
            int nl = msg.indexOf('\n');
            if (nl > 0) {
                msg = msg.substring(0, nl);
            }
            return msg.replaceFirst("^ORA-\\d+:\\s*", "");
        }

        return switch (code) {
            case 1     -> "That value already exists — it has to be unique.";
            case 1400  -> "A required field was left empty.";
            case 2291  -> "Referenced record does not exist "
                        + "(foreign key: the tutor, subject or slot is wrong).";
            case 2292  -> "Cannot delete this — other records still point at it.";
            case 2290  -> "A CHECK constraint rejected that value.";
            case 60    -> "Deadlock: two sessions were waiting on each other. "
                        + "Please try again.";
            default    -> "Database error " + code + ": " + e.getMessage();
        };
    }
}
