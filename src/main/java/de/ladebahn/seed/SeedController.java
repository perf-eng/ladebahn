package de.ladebahn.seed;

import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/admin")
public class SeedController {

    private final SeederService seeder;

    public SeedController(SeederService seeder) {
        this.seeder = seeder;
    }

    @PostMapping("/seed")
    public SeederService.SeedResult seed(
            @RequestParam(defaultValue = "small") String scale,
            @RequestParam(defaultValue = "42") long randomSeed) {
        return seeder.seed(SeedScale.from(scale), randomSeed);
    }
}