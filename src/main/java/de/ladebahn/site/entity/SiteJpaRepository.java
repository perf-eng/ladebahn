package de.ladebahn.site.entity;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface SiteJpaRepository extends JpaRepository<SiteEntity, Long> {

    /**
     * Fetches sites within a radius, ordered by distance — but returns only the
     * root entities. Every chargePoints / connectors / operator access afterwards
     * triggers its own query. This is lab 01.
     */
    @Query(value = """
        SELECT s.* FROM site s
        WHERE ST_DWithin(s.location, ST_MakePoint(:lon, :lat)::geography, :radiusMeters)
        ORDER BY ST_Distance(s.location, ST_MakePoint(:lon, :lat)::geography)
        LIMIT :limit OFFSET :offset
        """, nativeQuery = true)
    List<SiteEntity> findNearbyNaive(@Param("lat") double lat,
                                     @Param("lon") double lon,
                                     @Param("radiusMeters") double radiusMeters,
                                     @Param("limit") int limit,
                                     @Param("offset") int offset);
}