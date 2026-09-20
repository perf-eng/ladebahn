package de.ladebahn.site.entity;

import jakarta.persistence.*;

import java.math.BigDecimal;

@Entity
@Table(name = "connector")
public class ConnectorEntity {

    @Id
    private Long id;

    private Integer ordinal;
    private String type;

    @Column(name = "max_kw")
    private BigDecimal maxKw;

    private String status;

    @Version
    private Long version;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "charge_point_id")
    private ChargePointEntity chargePoint;

    public Long getId() { return id; }
    public Integer getOrdinal() { return ordinal; }
    public String getType() { return type; }
    public BigDecimal getMaxKw() { return maxKw; }
    public String getStatus() { return status; }
}