use anarogue_simulation::{RunOutcome, Simulation, SimulationConfig, Strategy};
use serde::Deserialize;
use serde_json::Value;

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
    file: String,
    scenario_seed: u32,
    strategy_id: String,
    max_turns: u32,
    outcome: RunOutcome,
    turns: u32,
    final_depth: u32,
    final_hp: i32,
    final_gold: u32,
    final_score: u32,
    final_potions: u32,
}

#[test]
fn godot_reference_runs_match() {
    let manifest: ReferenceManifest =
        serde_json::from_str(include_str!("../../examples/reference-v3/manifest-v3.json"))
            .expect("reference manifest must be valid JSON");

    for case in manifest.cases {
        let strategy: Strategy = case
            .strategy_id
            .parse()
            .unwrap_or_else(|error| panic!("{} has invalid strategy: {error}", case.name));
        let logged = Simulation::new_logged(
            SimulationConfig {
                scenario_seed: case.scenario_seed,
                strategy,
                map_width: manifest.map_size.width,
                map_height: manifest.map_size.height,
                max_turns: case.max_turns,
            },
            "rust-test.jsonl".to_owned(),
        )
        .unwrap_or_else(|error| panic!("{} could not start: {error}", case.name))
        .run_logged();
        let summary = logged.summary;

        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join(&case.file);
        let source = std::fs::read_to_string(path).expect("Godot reference log exists");
        let expected: Vec<Value> = source
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();
        assert_eq!(
            logged.events.len(),
            expected.len(),
            "{} event count",
            case.name
        );
        for (actual, mut expected) in logged.events.into_iter().zip(expected) {
            let mut actual = serde_json::to_value(actual).unwrap();
            for event in [&mut actual, &mut expected] {
                event.as_object_mut().unwrap().remove("time");
                event.as_object_mut().unwrap().remove("run_id");
                let details = event["details"].as_object_mut().unwrap();
                details.remove("log_file");
                details.remove("decision_id");
            }
            assert_eq!(actual, expected, "{} event parity", case.name);
        }

        assert_eq!(summary.outcome, case.outcome, "{} outcome", case.name);
        assert_eq!(summary.turns, case.turns, "{} turns", case.name);
        assert_eq!(summary.final_depth, case.final_depth, "{} depth", case.name);
        assert_eq!(summary.final_hp, case.final_hp, "{} hp", case.name);
        assert_eq!(summary.final_gold, case.final_gold, "{} gold", case.name);
        assert_eq!(summary.final_score, case.final_score, "{} score", case.name);
        assert_eq!(
            summary.final_potions, case.final_potions,
            "{} potions",
            case.name
        );
    }
}
