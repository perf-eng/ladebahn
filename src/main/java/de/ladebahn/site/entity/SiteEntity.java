package de.ladebahn.site.entity;

import jakarta.persistence.*;

import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "site")
public class SiteEntity {

    @Id
    private Long id;

    private String name;
    private String city;
    private String street;
    private String postcode;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "operator_id")
    private OperatorEntity operator;

    @OneToMany(mappedBy = "site", fetch = FetchType.LAZY)
    private List<ChargePointEntity> chargePoints = new ArrayList<>();

    public Long getId() { return id; }
    public String getName() { return name; }
    public String getCity() { return city; }
    public String getStreet() { return street; }
    public String getPostcode() { return postcode; }
    public OperatorEntity getOperator() { return operator; }
    public List<ChargePointEntity> getChargePoints() { return chargePoints; }
}