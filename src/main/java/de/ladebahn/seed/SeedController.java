package de.ladebahn.seed;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/admin")
public class SeedController {

    private final SeederService seeder;
    private final String token;

    public SeedController(SeederService seeder,
                          @Value("${ladebahn.labs.token}") String token) {
        this.seeder = seeder;
        this.token = token;
    }

    @PostMapping("/seed")
    public SeederService.SeedResult seed(
            @RequestParam(defaultValue = "small") String scale,
            @RequestParam(defaultValue = "42") long randomSeed,
            @RequestHeader(value = "X-Lab-Token", required = false) String provided) {

        if (!token.equals(provided)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "bad or missing X-Lab-Token");
        }
        return seeder.seed(SeedScale.from(scale), randomSeed);
    }
}