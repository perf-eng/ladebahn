package de.ladebahn.labs;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

@Component
public class IndexLab {

    private final JdbcTemplate jdbc;

    public IndexLab(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void apply(boolean enabled) {
        if (enabled) {
            jdbc.execute("DROP INDEX IF EXISTS idx_site_location");
        } else {
            jdbc.execute("""
                CREATE INDEX IF NOT EXISTS idx_site_location
                ON site USING GIST (location)
                """);
            jdbc.execute("ANALYZE site");
        }
    }
}