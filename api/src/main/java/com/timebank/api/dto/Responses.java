package com.timebank.api.dto;

import java.math.BigDecimal;

/** Response bodies that are not simply a model record. */
public final class Responses {

    private Responses() { }

    /** What the tutee gets back after booking. */
    public record BookingCreated(
            int bookingId, String sessionCode, double creditsHeld,
            String note) { }

    /**
     * The closed-economy audit.
     *
     * <pre>balances + escrow = grants - penalties</pre>
     *
     * Any non-zero drift means credits were created or destroyed outside
     * the ledger, which should be impossible.
     */
    public record Audit(
            BigDecimal balances, BigDecimal escrow,
            BigDecimal grantsLessPenalties, BigDecimal drift,
            boolean balanced) { }

    /** Generic acknowledgement for operations with nothing to return. */
    public record Ack(boolean ok, String message, int rowsAffected) { }
}
