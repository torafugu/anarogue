use anarogue_simulation::{Simulation, SimulationConfig, Strategy};
use std::process::ExitCode;

fn main() -> ExitCode {
    match parse_config().and_then(Simulation::new) {
        Ok(simulation) => {
            println!(
                "{}",
                serde_json::to_string(&simulation.run()).expect("summary is serializable")
            );
            ExitCode::SUCCESS
        }
        Err(message) => {
            eprintln!("error: {message}");
            eprintln!(
                "usage: anarogue-sim [--strategy aggressive|cautious] [--seed N] \
                 [--width N] [--height N] [--max-turns N]"
            );
            ExitCode::FAILURE
        }
    }
}

fn parse_config() -> Result<SimulationConfig, String> {
    let mut config = SimulationConfig {
        scenario_seed: 424_242,
        strategy: Strategy::AggressiveV1,
        map_width: 24,
        map_height: 18,
        max_turns: 120,
    };
    let mut arguments = std::env::args().skip(1);
    while let Some(argument) = arguments.next() {
        let value = arguments
            .next()
            .ok_or_else(|| format!("missing value for {argument}"))?;
        match argument.as_str() {
            "--strategy" => config.strategy = value.parse()?,
            "--seed" => config.scenario_seed = parse_number(&argument, &value)?,
            "--width" => config.map_width = parse_number(&argument, &value)?,
            "--height" => config.map_height = parse_number(&argument, &value)?,
            "--max-turns" => config.max_turns = parse_number(&argument, &value)?,
            _ => return Err(format!("unknown argument: {argument}")),
        }
    }
    config.validate()
}

fn parse_number<T>(argument: &str, value: &str) -> Result<T, String>
where
    T: std::str::FromStr,
{
    value
        .parse()
        .map_err(|_| format!("invalid value for {argument}: {value}"))
}
