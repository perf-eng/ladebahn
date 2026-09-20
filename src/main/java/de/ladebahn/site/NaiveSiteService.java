package de.ladebahn.site;

import de.ladebahn.site.entity.ChargePointEntity;
import de.ladebahn.site.entity.ConnectorEntity;
import de.ladebahn.site.entity.SiteEntity;
import de.ladebahn.site.entity.SiteJpaRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

/**
 * Lab 01 — the deliberately naive implementation.
 *
 * One query for the sites, then one per site for its charge points, then one per
 * charge point for its connectors, then one per site for its operator. With the
 * seeded fan-out (most sites have 2 charge points, ~600 have 24–40) the cost of a
 * page depends entirely on which sites it happens to contain.
 */
@Service
public class NaiveSiteService {

    private final SiteJpaRepository repository;

    public NaiveSiteService(SiteJpaRepository repository) {
        this.repository = repository;
    }

    @Transactional(readOnly = true)
    public List<SiteSummary> findNearby(double lat, double lon, double radiusMeters,
                                        int limit, int offset) {

        List<SiteEntity> sites = repository.findNearbyNaive(lat, lon, radiusMeters, limit, offset);
        List<SiteSummary> results = new ArrayList<>(sites.size());

        for (SiteEntity site : sites) {
            int total = 0;
            int available = 0;
            BigDecimal maxKw = BigDecimal.ZERO;

            // query per site
            for (ChargePointEntity cp : site.getChargePoints()) {
                // query per charge point
                for (ConnectorEntity c : cp.getConnectors()) {
                    total++;
                    if ("AVAILABLE".equals(c.getStatus())) available++;
                    if (c.getMaxKw() != null && c.getMaxKw().compareTo(maxKw) > 0) {
                        maxKw = c.getMaxKw();
                    }
                }
            }

            results.add(new SiteSummary(
                site.getId(),
                site.getName(),
                site.getCity(),
                site.getStreet(),
                site.getPostcode(),
                site.getOperator().getName(),   // another query per site
                null,   // lat  — not mapped on the entity
                null,   // lon
                null,   // distance — dropped on the naive path
                total,
                available,
                maxKw.doubleValue()
            ));
        }

        return results;
    }
}