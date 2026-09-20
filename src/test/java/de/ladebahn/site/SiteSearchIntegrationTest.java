package de.ladebahn.site;

import de.ladebahn.TestcontainersConfiguration;
import de.ladebahn.seed.SeedScale;
import de.ladebahn.seed.SeederService;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@Import(TestcontainersConfiguration.class)
class SiteSearchIntegrationTest {

    private static final double BERLIN_LAT = 52.5219;
    private static final double BERLIN_LON = 13.4132;

    @Autowired SiteService siteService;
    @Autowired SeederService seeder;

    private static boolean seeded = false;

    @BeforeAll
    static void resetFlag() {
        seeded = false;
    }

    void seedOnce() {
        if (!seeded) {
            seeder.seed(SeedScale.SMALL, 42L);
            seeded = true;
        }
    }

    @Test
    void findsSitesNearBerlin() {
        seedOnce();
        List<SiteSummary> results =
            siteService.findNearby(BERLIN_LAT, BERLIN_LON, 25, null, 0, 20);

        assertThat(results).isNotEmpty();
        assertThat(results).allSatisfy(s -> {
            assertThat(s.id()).isNotNull();
            assertThat(s.name()).isNotBlank();
            assertThat(s.totalConnectors()).isPositive();
            assertThat(s.availableConnectors()).isBetween(0, s.totalConnectors());
        });
    }

    @Test
    void resultsAreOrderedByDistance() {
        seedOnce();
        List<SiteSummary> results =
            siteService.findNearby(BERLIN_LAT, BERLIN_LON, 25, null, 0, 20);

        assertThat(results).extracting(SiteSummary::distanceM).isSorted();
    }

    @Test
    void respectsTheRadius() {
        seedOnce();
        List<SiteSummary> results =
            siteService.findNearby(BERLIN_LAT, BERLIN_LON, 5, null, 0, 100);

        assertThat(results).allSatisfy(s ->
            assertThat(s.distanceM()).isLessThanOrEqualTo(5000));
    }

    @Test
    void connectorTypeFilterNarrowsResults() {
        seedOnce();
        List<SiteSummary> all =
            siteService.findNearby(BERLIN_LAT, BERLIN_LON, 25, null, 0, 100);
        List<SiteSummary> ccs =
            siteService.findNearby(BERLIN_LAT, BERLIN_LON, 25, "CCS", 0, 100);

        assertThat(ccs.size()).isLessThanOrEqualTo(all.size());
    }

    @Test
    void paginationDoesNotOverlap() {
        seedOnce();
        List<SiteSummary> page0 =
            siteService.findNearby(BERLIN_LAT, BERLIN_LON, 25, null, 0, 5);
        List<SiteSummary> page1 =
            siteService.findNearby(BERLIN_LAT, BERLIN_LON, 25, null, 1, 5);

        assertThat(page0).extracting(SiteSummary::id)
            .doesNotContainAnyElementsOf(page1.stream().map(SiteSummary::id).toList());
    }
}