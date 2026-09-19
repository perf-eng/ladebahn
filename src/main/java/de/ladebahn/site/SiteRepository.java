package de.ladebahn.site;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public class SiteRepository {

    private final JdbcTemplate jdbc;

    public SiteRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    private static final String NEARBY_SQL = """
        SELECT s.id,
               s.name,
               s.city,
               s.street,
               s.postcode,
               o.name AS operator_name,
               ST_Y(s.location::geometry) AS lat,
               ST_X(s.location::geometry) AS lon,
               ST_Distance(s.location, ST_MakePoint(?, ?)::geography) AS distance_m,
               count(c.id)                                        AS total_connectors,
               count(c.id) FILTER (WHERE c.status = 'AVAILABLE')  AS available_connectors,
               max(c.max_kw)                                      AS max_kw
        FROM site s
        JOIN operator o      ON o.id = s.operator_id
        JOIN charge_point cp ON cp.site_id = s.id
        JOIN connector c     ON c.charge_point_id = cp.id
        WHERE ST_DWithin(s.location, ST_MakePoint(?, ?)::geography, ?)
          AND (?::text IS NULL OR c.type = ?::text)
        GROUP BY s.id, o.name
        ORDER BY distance_m
        LIMIT ? OFFSET ?
        """;

    public List<SiteSummary> findNearby(double lat, double lon, double radiusMeters,
                                        String connectorType, int limit, int offset) {
        return jdbc.query(NEARBY_SQL,
            (rs, rowNum) -> new SiteSummary(
                rs.getLong("id"),
                rs.getString("name"),
                rs.getString("city"),
                rs.getString("street"),
                rs.getString("postcode"),
                rs.getString("operator_name"),
                rs.getDouble("lat"),
                rs.getDouble("lon"),
                (int) Math.round(rs.getDouble("distance_m")),
                rs.getInt("total_connectors"),
                rs.getInt("available_connectors"),
                rs.getDouble("max_kw")
            ),
            lon, lat,              // ST_Distance origin  (X, Y = lon, lat)
            lon, lat, radiusMeters,// ST_DWithin origin and radius
            connectorType, connectorType,
            limit, offset);
    }
}