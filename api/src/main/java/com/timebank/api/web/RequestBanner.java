package com.timebank.api.web;

import com.timebank.db.SqlLog;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Prints one block per request the Flutter app makes.
 *
 * <p>Together with {@link SqlLog} this turns the API console into a live
 * trace of the whole stack: one tap in the app prints the HTTP request
 * it caused, every SQL statement that request ran with its bind values,
 * row counts and timings, and the response status — as a single block.
 *
 * <p>WHY A SINGLE BLOCK
 * Opening a screen fires half a dozen requests at once, each handled on
 * its own thread. Printing as they went interleaved them, so a row count
 * appeared under another request's query. The request's output is now
 * collected while it runs and printed in one call at the end, so a block
 * always holds one request's work, in order, and the window can be read
 * over someone's shoulder.
 *
 * <p>OPTIONS requests are skipped. The browser sends one before every
 * cross-origin call to ask what is allowed; they run no SQL and are pure
 * noise in a demo.
 */
@Configuration
public class RequestBanner implements WebMvcConfigurer, HandlerInterceptor {

    private static final String START  = "timebank.start";
    private static final String HEADER = "timebank.header";

    private static final String BAR =
            "================================================================";

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(this).addPathPatterns("/api/**");
    }

    @Override
    public boolean preHandle(HttpServletRequest req, HttpServletResponse res,
                             Object handler) {
        if (isPreflight(req)) {
            return true;
        }

        req.setAttribute(START, System.nanoTime());

        String query = req.getQueryString();
        String path  = req.getRequestURI() + (query == null ? "" : "?" + query);

        req.setAttribute(HEADER, String.format(
                "%n%n%s%n  APP REQUEST   %s %s%n%s%n",
                BAR, req.getMethod(), path, BAR));

        // From here until afterCompletion, this thread's SQL is collected
        // rather than printed.
        SqlLog.beginCapture();
        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest req, HttpServletResponse res,
                                Object handler, Exception ex) {
        if (isPreflight(req)) {
            return;
        }

        String sql = SqlLog.endCapture();

        Object started = req.getAttribute(START);
        double ms = (started instanceof Long t)
                  ? (System.nanoTime() - t) / 1_000_000.0
                  : 0.0;

        String header = String.valueOf(req.getAttribute(HEADER));
        String footer = String.format(
                "%n  DONE   HTTP %d   total %.1f ms%n%s%n", res.getStatus(), ms, BAR);

        // One call, so two requests finishing together cannot interleave.
        System.out.print(header + sql + footer);
    }

    private static boolean isPreflight(HttpServletRequest req) {
        return "OPTIONS".equalsIgnoreCase(req.getMethod());
    }
}
