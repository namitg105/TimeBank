package com.timebank.model;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * One immutable row of CREDIT_TXN.
 *
 * <p>{@code bookingId} is an Integer rather than an int because it is the
 * only nullable foreign key in the database: a GRANT or PENALTY has no
 * originating session. That nullability is the partial participation of
 * CREDIT_TXN in the "generates" relationship, showing up in Java.
 */
public record LedgerEntry(
        long          txnId,
        String        studentName,
        String        txnType,
        BigDecimal    amount,          // signed: + in, - out
        BigDecimal    balanceAfter,
        LocalDateTime postedAt,
        Integer       bookingId,       // null for GRANT / PENALTY
        String        remarks
) {
    public String origin() {
        return bookingId == null ? "system credit" : "session " + bookingId;
    }

    @Override
    public String toString() {
        return String.format("%-6d %-16s %-9s %+6s  bal %6s  %s",
                txnId, studentName, txnType, amount, balanceAfter, origin());
    }
}
