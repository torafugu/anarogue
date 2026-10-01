use anarogue_simulation::{RunOutcome, Simulation, SimulationConfig, Strategy};
use serde::Deserialize;

#[derive(Deserialize)]
struct ReferenceManifest {
    map_size: MapSize,
    cases: Vec<ReferenceCase>,
}

#[derive(Deserialize)]
struct MapSize {
    width: i32,
    height: i32,
}

#[derive(Deserialize)]
struct ReferenceCase {
    name: String,
    scenario_seed: u32,
    strategy_id: String,
    max_turns: u32,
    outcome: RunOutcome,
    turns: u32,
    final_depth: u32,
    final_hp: i32,
    final_gold: u32,
    final_score: u32,
}

#[test]
fn godot_reference_runs_match() {
    let manifest: ReferenceManifest =
        serde_json::from_str(include_str!("../../examples/reference-v2/manifest-v2.json"))
            .expect("reference manifest must be valid JSON");

    for case in manifest.cases {
        let strategy: Strategy = case
            .strategy_id
            .parse()
            .unwrap_or_else(|error| panic!("{} has invalid strategy: {error}", case.name));
        let summary = Simulation::new(SimulationConfig {
            scenario_seed: case.scenario_seed,
            strategy,
            map_width: manifest.map_size.width,
            map_height: manifest.map_size.height,
            max_turns: case.max_turns,
        })
        .unwrap_or_else(|error| panic!("{} could not start: {error}", case.name))
        .run();

        assert_eq!(summary.outcome, case.outcome, "{} outcome", case.name);
        assert_eq!(summary.turns, case.turns, "{} turns", case.name);
        assert_eq!(summary.final_depth, case.final_depth, "{} depth", case.name);
        assert_eq!(summary.final_hp, case.final_hp, "{} hp", case.name);
        assert_eq!(summary.final_gold, case.final_gold, "{} gold", case.name);
        assert_eq!(summary.final_score, case.final_score, "{} score", case.name);
    }
}
