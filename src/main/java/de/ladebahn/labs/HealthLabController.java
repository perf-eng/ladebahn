package de.ladebahn.labs;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/health")
public class HealthLabController {

    @GetMapping("/slow")
    public Map<String, Object> slow(@RequestParam(defaultValue = "0") long ms)
            throws InterruptedException {
        if (ms > 0) Thread.sleep(ms);
        return Map.of(
            "sleptMs", ms,
            "thread", Thread.currentThread().toString()
        );
    }
}
