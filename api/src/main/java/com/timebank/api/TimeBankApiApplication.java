package com.timebank.api;

import com.timebank.db.Database;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.sql.SQLException;

/**
 * The bridge between the Flutter app and Oracle.
 *
 * <p>Flutter cannot use JDBC — JDBC is a Java API and there is no Oracle
 * driver for Dart. So the app speaks HTTP/JSON to this service, and this
 * service speaks JDBC to Oracle. All the database work still happens in
 * Java, through the same DAO classes the console app uses.
 *
 * <p>Spring's own DataSource auto-configuration is switched off: the
 * project manages its own Oracle UCP pool in {@link Database}, and two
 * competing pools would be a mess.
 */
@SpringBootApplication(exclude = DataSourceAutoConfiguration.class)
public class TimeBankApiApplication {

    public static void main(String[] args) throws SQLException {
        // Fail fast: if Oracle is unreachable, say so now rather than on
        // the first request from the phone.
        Database.init();
        System.out.println("Oracle pool ready.");
        SpringApplication.run(TimeBankApiApplication.class, args);
    }

    /**
     * Allows the Flutter app to call this API from a browser.
     *
     * <p>Only needed for Flutter Web: a browser blocks cross-origin
     * requests unless the server opts in. Android, iOS and desktop builds
     * are not subject to that rule.
     */
    @Bean
    public WebMvcConfigurer corsConfigurer() {
        return new WebMvcConfigurer() {
            @Override
            public void addCorsMappings(CorsRegistry registry) {
                registry.addMapping("/api/**")
                        .allowedOriginPatterns("*")
                        .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS");
            }
        };
    }
}
