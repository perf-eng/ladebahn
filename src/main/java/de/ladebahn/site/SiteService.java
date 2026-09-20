package de.ladebahn.site;

import de.ladebahn.labs.LabSwitchboard;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class SiteService {

    private final SiteRepository repository;
    private final NaiveSiteService naive;
    private final LabSwitchboard labs;

    public SiteService(SiteRepository repository, NaiveSiteService naive, LabSwitchboard labs) {
        this.repository = repository;
        this.naive = naive;
        this.labs = labs;
    }

    public List<SiteSummary> findNearby(double lat, double lon, double radiusKm,
                                        String connectorType, int page, int size) {

        if (labs.on(LabSwitchboard.SLOW_RESPONSE)) {
            try {
                Thread.sleep(labs.param(LabSwitchboard.SLOW_RESPONSE));
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }

        double radiusMeters = radiusKm * 1000;
        int offset = page * size;

        if (labs.on(LabSwitchboard.N_PLUS_ONE)) {
            return naive.findNearby(lat, lon, radiusMeters, size, offset);
        }

        return repository.findNearby(lat, lon, radiusMeters, connectorType, size, offset);
    }
}