package de.ladebahn.site;

import jakarta.validation.constraints.*;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/sites")
@Validated
public class SiteController {

    private final SiteService service;

    public SiteController(SiteService service) {
        this.service = service;
    }

    @GetMapping("/nearby")
    public NearbyResponse nearby(
            @RequestParam @DecimalMin("-90")  @DecimalMax("90")  double lat,
            @RequestParam @DecimalMin("-180") @DecimalMax("180") double lon,
            @RequestParam(defaultValue = "5")  @DecimalMin("0.1") @DecimalMax("100") double radiusKm,
            @RequestParam(required = false) String connectorType,
            @RequestParam(defaultValue = "0")  @Min(0)  int page,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int size) {

        long started = System.nanoTime();
        List<SiteSummary> results = service.findNearby(lat, lon, radiusKm, connectorType, page, size);
        long tookMs = (System.nanoTime() - started) / 1_000_000;

        return new NearbyResponse(results.size(), page, size, radiusKm, tookMs, results);
    }

    public record NearbyResponse(
        int count, int page, int size, double radiusKm, long queryTimeMs,
        List<SiteSummary> sites
    ) {}
}