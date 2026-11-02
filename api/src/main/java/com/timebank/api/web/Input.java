package com.timebank.api.web;

import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.Map;

/**
 * Reads and checks what a form sent, before anything touches the database.
 *
 * <p>Every failure is an IllegalArgumentException carrying one sentence
 * the app shows as it is; GlobalExceptionHandler turns it into a 400.
 * Checking here first means a request either passes completely or
 * changes nothing — no half-created student when the phone was wrong.
 */
final class Input {

    private Input() { }

    /** Trimmed text, or null when missing or blank. */
    static String text(Object o) {
        if (o == null) return null;
        String s = String.valueOf(o).trim();
        return s.isEmpty() ? null : s;
    }

    static String required(Object o, String messageIfMissing) {
        String s = text(o);
        if (s == null) throw new IllegalArgumentException(messageIfMissing);
        return s;
    }

    static int integer(Object o, String messageIfBad) {
        if (o instanceof Number n) return n.intValue();
        try {
            return Integer.parseInt(String.valueOf(o).trim());
        } catch (RuntimeException e) {
            throw new IllegalArgumentException(messageIfBad);
        }
    }

    static double decimal(Object o, String messageIfBad) {
        if (o instanceof Number n) return n.doubleValue();
        try {
            return Double.parseDouble(String.valueOf(o).trim());
        } catch (RuntimeException e) {
            throw new IllegalArgumentException(messageIfBad);
        }
    }

    /** Upper-cases the value and requires it to be one of {@code allowed}. */
    static String oneOf(Object o, String messageIfBad, String... allowed) {
        String s = text(o);
        if (s != null) {
            s = s.toUpperCase();
            for (String a : allowed) {
                if (a.equals(s)) return s;
            }
        }
        throw new IllegalArgumentException(messageIfBad);
    }

    static LocalDate date(Object o, String messageIfBad) {
        String s = text(o);
        if (s == null) throw new IllegalArgumentException(messageIfBad);
        try {
            return LocalDate.parse(s);
        } catch (DateTimeParseException e) {
            throw new IllegalArgumentException(messageIfBad);
        }
    }

    /** Exactly ten digits, the CHK_PHONE_DIGITS rule, checked before the INSERT. */
    static String phone(Object o) {
        String s = text(o);
        if (s == null || !s.matches("\\d{10}")) {
            throw new IllegalArgumentException("A phone number must be exactly 10 digits.");
        }
        return s;
    }

    static String maxLength(String value, int max, String label) {
        if (value != null && value.length() > max) {
            throw new IllegalArgumentException(
                    label + " is too long. Use at most " + max + " characters.");
        }
        return value;
    }

    /** The details every new student needs, checked the same way for sign-up and for the admin's form. */
    record NewStudent(String regNo, String firstName, String lastName, String email,
                      LocalDate dob, int deptId, String block, String roomNo,
                      String city, String phone) { }

    static NewStudent newStudent(Map<String, Object> body) {
        String regNo = required(body.get("regNo"), "Enter a registration number.").toUpperCase();
        if (!regNo.matches("[A-Z0-9]{5,15}")) {
            throw new IllegalArgumentException(
                    "A registration number uses only letters and digits, like 25BCE1001.");
        }
        String first = maxLength(required(body.get("firstName"), "Enter a first name."), 40, "First name");
        String last  = maxLength(required(body.get("lastName"), "Enter a last name."), 40, "Last name");

        String email = maxLength(required(body.get("email"), "Enter an email address."), 80, "Email");
        if (!email.matches("[^@\\s]+@[^@\\s]+\\.[^@\\s]+")) {
            throw new IllegalArgumentException("That email address does not look right.");
        }

        LocalDate dob = date(body.get("dob"), "Pick a valid date of birth.");
        if (!dob.isBefore(LocalDate.now().minusYears(15))) {
            throw new IllegalArgumentException("A student must be at least 15 years old.");
        }
        if (dob.isBefore(LocalDate.now().minusYears(100))) {
            throw new IllegalArgumentException("That date of birth is too far in the past.");
        }

        int deptId = body.get("deptId") == null ? 1
                   : integer(body.get("deptId"), "Pick a department from the list.");

        String phone = text(body.get("phone")) == null ? null : phone(body.get("phone"));

        return new NewStudent(regNo, first, last, email, dob, deptId,
                maxLength(text(body.get("block")), 20, "Block"),
                maxLength(text(body.get("roomNo")), 10, "Room"),
                maxLength(text(body.get("city")), 40, "Home city"),
                phone);
    }
}
