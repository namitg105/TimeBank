package com.timebank.api.web;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Prints a banner for every request the Flutter app makes.
 *
 * <p>Together with {@link com.timebank.db.SqlLog} this turns the API
 * console into a live trace of the whole stack: one tap in the app
 * prints the HTTP request it caused, then every SQL statement that
 * request ran, with its bind values, row counts and timings, then the
 * response status.
 *
 * <p>That is the point of it. A screen full of data proves nothing by
 * itself; watching the SQL scroll past as the button is pressed is what
 * shows the database is really doing the work.
 */
@Configuration
public class RequestBanner implements WebMvcConfigurer, HandlerInterceptor {

    private static final String START = "timebank.start";

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(this).addPathPatterns("/api/**");
    }

    @Override
    public boolean preHandle(HttpServletRequest req, HttpServletResponse res,
                             Object handler) {
        req.setAttribute(START, System.nanoTime());

        String query = req.getQueryString();
        String path  = req.getRequestURI() + (query == null ? "" : "?" + query);

        System.out.printf(
            "%n%n"
          + "================================================================%n"
          + "  APP REQUEST   %s %s%n"
          + "================================================================%n",
            req.getMethod(), path);

        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest req, HttpServletResponse res,
                                Object handler, Exception ex) {
        Object started = req.getAttribute(START);
        double ms = (started instanceof Long t)
                  ? (System.nanoTime() - t) / 1_000_000.0
                  : 0.0;

        System.out.printf(
            "%n  APP REQUEST DONE   HTTP %d   total %.1f ms%n"
          + "================================================================%n%n",
            res.getStatus(), ms);
    }
}
