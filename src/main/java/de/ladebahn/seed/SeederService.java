package de.ladebahn.seed;

import de.ladebahn.seed.GermanGeography.City;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

@Service
public class SeederService {

    private static final String[] CONNECTOR_TYPES = {"TYPE2", "CCS", "CHADEMO"};
    private static final double[] POWER_LEVELS    = {11, 22, 50, 150, 300, 400};
    private static final String[] STATUSES        = {"AVAILABLE", "OCCUPIED", "FAULTED", "UNAVAILABLE"};

    private final JdbcTemplate jdbc;

    public SeederService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** Deterministic: same seed value always produces the same dataset. */
    @Transactional
    public SeedResult seed(SeedScale scale, long randomSeed) {
        long start = System.currentTimeMillis();
        Random rnd = new Random(randomSeed);

        truncateAll();
        List<Long> operatorIds = insertOperators(scale, rnd);
        List<Long> siteIds     = insertSites(scale, operatorIds, rnd);
        int chargePoints       = insertChargePoints(siteIds, rnd);
        int connectors         = insertConnectors(rnd);

        jdbc.execute("ANALYZE");

        return new SeedResult(scale.name(), operatorIds.size(), siteIds.size(),
                              chargePoints, connectors, System.currentTimeMillis() - start);
    }

    private void truncateAll() {
        jdbc.execute("TRUNCATE connector, charge_point, site, operator RESTART IDENTITY CASCADE");
    }

    private List<Long> insertOperators(SeedScale scale, Random rnd) {
        List<Object[]> batch = new ArrayList<>();
        for (int i = 0; i < scale.operators; i++) {
            String base = GermanGeography.OPERATORS[i % GermanGeography.OPERATORS.length];
            String name = i < GermanGeography.OPERATORS.length ? base : base + " " + (i / 10 + 1);
            batch.add(new Object[]{name, "DE"});
        }
        jdbc.batchUpdate("INSERT INTO operator (name, country) VALUES (?, ?)", batch);
        return jdbc.queryForList("SELECT id FROM operator ORDER BY id", Long.class);
    }

    /**
     * Sites cluster around cities (70%) or scatter along corridors (30%).
     * Popularity follows a Zipf-like curve: a few sites absorb most traffic.
     */
    private List<Long> insertSites(SeedScale scale, List<Long> operatorIds, Random rnd) {
        List<Object[]> batch = new ArrayList<>(scale.sites);

        for (int i = 0; i < scale.sites; i++) {
            double lat, lon;
            String city;

            if (rnd.nextDouble() < 0.70) {
                City c = pickWeightedCity(rnd);
                city = c.name();
                double radiusKm = Math.abs(rnd.nextGaussian()) * 8.0;      // tight urban cluster
                double bearing  = rnd.nextDouble() * 2 * Math.PI;
                lat = c.lat() + (radiusKm / 111.0) * Math.cos(bearing);
                lon = c.lon() + (radiusKm / (111.0 * Math.cos(Math.toRadians(c.lat())))) * Math.sin(bearing);
            } else {
                City c = pickWeightedCity(rnd);
                city = c.name() + " Umland";
                double radiusKm = 20 + rnd.nextDouble() * 90;               // motorway corridor
                double bearing  = rnd.nextDouble() * 2 * Math.PI;
                lat = c.lat() + (radiusKm / 111.0) * Math.cos(bearing);
                lon = c.lon() + (radiusKm / (111.0 * Math.cos(Math.toRadians(c.lat())))) * Math.sin(bearing);
            }

            double popularity = 1.0 / Math.pow(i + 1, 0.8);                 // Zipf
            String street = GermanGeography.STREETS[rnd.nextInt(GermanGeography.STREETS.length)]
                          + " " + (1 + rnd.nextInt(180));
            String postcode = String.format("%05d", 10000 + rnd.nextInt(89999));
            long operatorId = operatorIds.get(rnd.nextInt(operatorIds.size()));

            batch.add(new Object[]{operatorId, city + " " + street, street, city, postcode,
                                   lon, lat, popularity});
        }

        jdbc.batchUpdate("""
            INSERT INTO site (operator_id, name, street, city, postcode, location, popularity)
            VALUES (?, ?, ?, ?, ?, ST_MakePoint(?, ?)::geography, ?)
            """, batch);

        return jdbc.queryForList("SELECT id FROM site ORDER BY id", Long.class);
    }

    /** Fan-out is deliberately skewed: most sites are small, a few are hubs. */
    private int insertChargePoints(List<Long> siteIds, Random rnd) {
        List<Object[]> batch = new ArrayList<>();
        int serial = 0;

        for (Long siteId : siteIds) {
            double roll = rnd.nextDouble();
            int count = roll < 0.60 ? 2
                      : roll < 0.85 ? 4
                      : roll < 0.97 ? 8 + rnd.nextInt(8)
                      : 24 + rnd.nextInt(17);                               // rare mega-hub

            for (int i = 0; i < count; i++) {
                batch.add(new Object[]{
                    siteId,
                    String.format("DE*LDB*E%08d", serial++),
                    GermanGeography.VENDORS[rnd.nextInt(GermanGeography.VENDORS.length)],
                    GermanGeography.MODELS[rnd.nextInt(GermanGeography.MODELS.length)],
                    "1." + rnd.nextInt(9) + "." + rnd.nextInt(20),
                    rnd.nextDouble() < 0.95 ? "ONLINE" : "OFFLINE"
                });
            }
        }

        jdbc.batchUpdate("""
            INSERT INTO charge_point (site_id, serial, vendor, model, firmware, status, last_seen)
            VALUES (?, ?, ?, ?, ?, ?, now())
            """, batch);
        return batch.size();
    }

    private int insertConnectors(Random rnd) {
        List<Long> chargePointIds = jdbc.queryForList("SELECT id FROM charge_point ORDER BY id", Long.class);
        List<Object[]> batch = new ArrayList<>();

        for (Long cpId : chargePointIds) {
            int count = rnd.nextDouble() < 0.45 ? 1 : 2;
            for (int ordinal = 1; ordinal <= count; ordinal++) {
                double roll = rnd.nextDouble();
                String status = roll < 0.62 ? "AVAILABLE"
                              : roll < 0.90 ? "OCCUPIED"
                              : roll < 0.96 ? "UNAVAILABLE"
                              : "FAULTED";
                batch.add(new Object[]{
                    cpId, ordinal,
                    CONNECTOR_TYPES[rnd.nextInt(CONNECTOR_TYPES.length)],
                    POWER_LEVELS[rnd.nextInt(POWER_LEVELS.length)],
                    status
                });
            }
        }

        jdbc.batchUpdate("""
            INSERT INTO connector (charge_point_id, ordinal, type, max_kw, status)
            VALUES (?, ?, ?, ?, ?)
            """, batch);
        return batch.size();
    }

    private City pickWeightedCity(Random rnd) {
        double roll = rnd.nextDouble(), cumulative = 0;
        for (City c : GermanGeography.CITIES) {
            cumulative += c.weight();
            if (roll <= cumulative) return c;
        }
        return GermanGeography.CITIES.get(0);
    }

    public record SeedResult(String scale, int operators, int sites,
                             int chargePoints, int connectors, long millis) {}
}