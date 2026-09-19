package de.ladebahn.site;

import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class SiteService {

    private final SiteRepository repository;

    public SiteService(SiteRepository repository) {
        this.repository = repository;
    }

    public List<SiteSummary> findNearby(double lat, double lon, double radiusKm,
                                        String connectorType, int page, int size) {
        return repository.findNearby(lat, lon, radiusKm * 1000,
                                     connectorType, size, page * size);
    }
}