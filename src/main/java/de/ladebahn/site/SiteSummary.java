package de.ladebahn.site;

public record SiteSummary(
    Long id,
    String name,
    String city,
    String street,
    String postcode,
    String operatorName,
    Double lat,
    Double lon,
    Integer distanceM,
    Integer totalConnectors,
    Integer availableConnectors,
    Double maxKw
) {}