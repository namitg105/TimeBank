package com.timebank.api.web;

/**
 * The error shape every failed request returns, so the Flutter app only
 * ever has to parse one thing.
 *
 * @param error   short machine-readable kind, e.g. "RULE_VIOLATION"
 * @param message a sentence already written for a human — for our own
 *                ORA-20001..20021 errors this is the text the trigger or
 *                package raised, which is why those messages are worded
 *                the way they are
 * @param code    the original Oracle error number, useful when debugging
 */
public record ApiError(String error, String message, int code) { }
