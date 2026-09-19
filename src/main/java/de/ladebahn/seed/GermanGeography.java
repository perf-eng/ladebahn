package de.ladebahn.seed;

import java.util.List;

/** Real German population centres, used to cluster generated sites realistically. */
final class GermanGeography {

    record City(String name, double lat, double lon, double weight) {}

    /** weight = relative share of sites placed near this city. */
    static final List<City> CITIES = List.of(
        new City("Berlin",     52.5200, 13.4050, 0.16),
        new City("Hamburg",    53.5511,  9.9937, 0.10),
        new City("München",    48.1351, 11.5820, 0.11),
        new City("Köln",       50.9375,  6.9603, 0.08),
        new City("Frankfurt",  50.1109,  8.6821, 0.09),
        new City("Stuttgart",  48.7758,  9.1829, 0.07),
        new City("Düsseldorf", 51.2277,  6.7735, 0.06),
        new City("Leipzig",    51.3397, 12.3731, 0.05),
        new City("Dortmund",   51.5136,  7.4653, 0.05),
        new City("Essen",      51.4556,  7.0116, 0.04),
        new City("Bremen",     53.0793,  8.8017, 0.04),
        new City("Dresden",    51.0504, 13.7373, 0.04),
        new City("Hannover",   52.3759,  9.7320, 0.04),
        new City("Nürnberg",   49.4521, 11.0767, 0.04),
        new City("Mannheim",   49.4875,  8.4660, 0.03)
    );

    static final String[] VENDORS   = {"ABB", "Alpitronic", "Siemens", "Compleo", "Kempower", "Tritium"};
    static final String[] MODELS    = {"Terra 184", "HYC300", "Sicharge D", "eBox Pro", "Satellite", "PKM150"};
    static final String[] OPERATORS = {"Ionity", "EnBW mobility+", "Allego", "Fastned", "Aral pulse",
                                       "Shell Recharge", "EWE Go", "Mer", "Pfalzwerke", "Vattenfall InCharge"};
    static final String[] STREETS   = {"Hauptstraße", "Bahnhofstraße", "Industriestraße", "Am Kreuz",
                                       "Raststätte Nord", "Gewerbepark", "Marktplatz", "Autohof West"};

    private GermanGeography() {}
}