use anarogue_simulation::{GoalPolicy, RunLogEvent, Simulation, SimulationConfig, Strategy};
use std::fs::{create_dir_all, File};
use std::io::{BufWriter, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("error: {message}");
            eprintln!(
                "usage: anarogue-sim [--strategy aggressive|cautious] [--seed N] \
                 [--width N] [--height N] [--max-turns N] [--output PATH] [--enemy-weight N] [--item-weight N] [--stairs-weight N] [--temperature N]"
            );
            ExitCode::FAILURE
        }
    }
}

struct CliOptions {
    config: SimulationConfig,
    output: Option<PathBuf>,
    policy: GoalPolicy,
}

fn run() -> Result<(), String> {
    let options = parse_options()?;
    if let Some(output) = options.output {
        let display_path = output.to_string_lossy().into_owned();
        let logged_run =
            Simulation::new_logged_with_policy(options.config, display_path, options.policy)?
                .run_logged();
        write_jsonl(&output, &logged_run.events)?;
        println!(
            "{}",
            serde_json::to_string(&logged_run.summary).expect("summary is serializable")
        );
    } else {
        let summary = Simulation::new_with_policy(options.config, options.policy)?.run();
        println!(
            "{}",
            serde_json::to_string(&summary).expect("summary is serializable")
        );
    }
    Ok(())
}

fn write_jsonl(path: &Path, events: &[RunLogEvent]) -> Result<(), String> {
    if let Some(parent) = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        create_dir_all(parent)
            .map_err(|error| format!("could not create {}: {error}", parent.display()))?;
    }
    let file = File::create(path)
        .map_err(|error| format!("could not create {}: {error}", path.display()))?;
    let mut writer = BufWriter::new(file);
    for event in events {
        serde_json::to_writer(&mut writer, event)
            .map_err(|error| format!("could not serialize run event: {error}"))?;
        writer
            .write_all(b"\n")
            .map_err(|error| format!("could not write {}: {error}", path.display()))?;
    }
    writer
        .flush()
        .map_err(|error| format!("could not flush {}: {error}", path.display()))
}

fn parse_options() -> Result<CliOptions, String> {
    let mut config = SimulationConfig {
        scenario_seed: 424_242,
        strategy: Strategy::AggressiveV1,
        map_width: 24,
        map_height: 18,
        max_turns: 120,
    };
    let mut output = None;
    let mut weights = [None; 4];
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
            "--enemy-weight" => weights[0] = Some(parse_number(&argument, &value)?),
            "--item-weight" => weights[1] = Some(parse_number(&argument, &value)?),
            "--stairs-weight" => weights[2] = Some(parse_number(&argument, &value)?),
            "--temperature" => weights[3] = Some(parse_number(&argument, &value)?),
            "--output" => output = Some(PathBuf::from(value)),
            _ => return Err(format!("unknown argument: {argument}")),
        }
    }
    let mut policy = GoalPolicy::preset(config.strategy);
    policy.enemy_weight = weights[0].unwrap_or(policy.enemy_weight);
    policy.item_weight = weights[1].unwrap_or(policy.item_weight);
    policy.stairs_weight = weights[2].unwrap_or(policy.stairs_weight);
    policy.temperature = weights[3].unwrap_or(policy.temperature);
    Ok(CliOptions {
        config: config.validate()?,
        policy: policy.validate()?,
        output,
    })
}

fn parse_number<T>(argument: &str, value: &str) -> Result<T, String>
where
    T: std::str::FromStr,
{
    value
        .parse()
        .map_err(|_| format!("invalid value for {argument}: {value}"))
}
