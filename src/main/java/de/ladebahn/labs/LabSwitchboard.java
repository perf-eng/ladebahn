package de.ladebahn.labs;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class LabSwitchboard {

    public static final String N_PLUS_ONE    = "n_plus_one";
    public static final String DROP_INDEX    = "drop_index";
    public static final String SLOW_RESPONSE = "slow_response";

    private static final List<String> KNOWN =
        List.of(N_PLUS_ONE, DROP_INDEX, SLOW_RESPONSE);

    private final Map<String, Boolean> state  = new ConcurrentHashMap<>();
    private final Map<String, Integer> params = new ConcurrentHashMap<>();

    public LabSwitchboard(MeterRegistry registry) {
        for (String lab : KNOWN) {
            state.put(lab, false);
            Gauge.builder("ladebahn.lab.active", state,
                          m -> Boolean.TRUE.equals(m.get(lab)) ? 1.0 : 0.0)
                 .tag("lab", lab)
                 .description("1 when the named fault-injection lab is enabled")
                 .register(registry);
        }
        params.put(SLOW_RESPONSE, 250);
    }

    public boolean on(String lab) {
        return Boolean.TRUE.equals(state.get(lab));
    }

    public int param(String lab) {
        return params.getOrDefault(lab, 0);
    }

    public void set(String lab, boolean enabled, Integer param) {
        if (!state.containsKey(lab)) {
            throw new IllegalArgumentException("unknown lab: " + lab);
        }
        if (param != null) params.put(lab, param);
        state.put(lab, enabled);
    }

    public Map<String, Object> snapshot() {
        return Map.of("labs", Map.copyOf(state), "params", Map.copyOf(params));
    }

    public List<String> known() {
        return KNOWN;
    }
}