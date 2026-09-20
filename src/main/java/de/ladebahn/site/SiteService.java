package de.ladebahn.site;

import de.ladebahn.labs.LabSwitchboard;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class SiteService {

    private final SiteRepository repository;
    private final LabSwitchboard labs;

    public SiteService(SiteRepository repository, LabSwitchboard labs) {
        this.repository = repository;
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
        return repository.findNearby(lat, lon, radiusKm * 1000,
                                     connectorType, size, page * size);
    }
}