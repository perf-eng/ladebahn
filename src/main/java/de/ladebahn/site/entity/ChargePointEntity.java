package de.ladebahn.site.entity;

import jakarta.persistence.*;

import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "charge_point")
public class ChargePointEntity {

    @Id
    private Long id;

    private String serial;
    private String vendor;
    private String model;
    private String status;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "site_id")
    private SiteEntity site;

    @OneToMany(mappedBy = "chargePoint", fetch = FetchType.LAZY)
    private List<ConnectorEntity> connectors = new ArrayList<>();

    public Long getId() { return id; }
    public String getSerial() { return serial; }
    public String getStatus() { return status; }
    public SiteEntity getSite() { return site; }
    public List<ConnectorEntity> getConnectors() { return connectors; }
}