package de.ladebahn.site.entity;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "operator")
public class OperatorEntity {

    @Id
    private Long id;

    private String name;

    @JdbcTypeCode(SqlTypes.CHAR)
    private String country;

    public Long getId() { return id; }
    public String getName() { return name; }
    public String getCountry() { return country; }
}