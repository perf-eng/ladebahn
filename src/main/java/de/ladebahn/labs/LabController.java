package de.ladebahn.labs;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.Map;

@RestController
@RequestMapping("/labs")
public class LabController {

    private final LabSwitchboard switchboard;
    private final IndexLab indexLab;
    private final String token;

    public LabController(LabSwitchboard switchboard, IndexLab indexLab,
                         @Value("${ladebahn.labs.token}") String token) {
        this.switchboard = switchboard;
        this.indexLab = indexLab;
        this.token = token;
    }

    @GetMapping
    public Map<String, Object> list() {
        return switchboard.snapshot();
    }

    @PostMapping("/{lab}/enable")
    public ResponseEntity<Map<String, Object>> enable(
            @PathVariable String lab,
            @RequestParam(required = false) Integer param,
            @RequestHeader(value = "X-Lab-Token", required = false) String provided) {
        return toggle(lab, true, param, provided);
    }

    @PostMapping("/{lab}/disable")
    public ResponseEntity<Map<String, Object>> disable(
            @PathVariable String lab,
            @RequestHeader(value = "X-Lab-Token", required = false) String provided) {
        return toggle(lab, false, null, provided);
    }

    private ResponseEntity<Map<String, Object>> toggle(
            String lab, boolean enabled, Integer param, String provided) {

        if (!token.equals(provided)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "bad or missing X-Lab-Token");
        }
        if (!switchboard.known().contains(lab)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "unknown lab, known: " + switchboard.known());
        }

        switchboard.set(lab, enabled, param);

        if (LabSwitchboard.DROP_INDEX.equals(lab)) {
            indexLab.apply(enabled);
        }

        return ResponseEntity.ok(switchboard.snapshot());
    }
}