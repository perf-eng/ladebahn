package de.ladebahn.seed;

public enum SeedScale {
    SMALL(5, 200),
    MEDIUM(20, 2_000),
    LARGE(50, 20_000);

    public final int operators;
    public final int sites;

    SeedScale(int operators, int sites) {
        this.operators = operators;
        this.sites = sites;
    }

    public static SeedScale from(String value) {
        return valueOf(value.toUpperCase());
    }
}