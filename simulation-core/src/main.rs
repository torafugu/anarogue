use anarogue_simulation::run_store::save_run;
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
                 [--width N] [--height N] [--max-turns N] [--output PATH] [--enemy-weight N] [--item-weight N] [--stairs-weight N] [--temperature N] [--db PATH] [--revision REV]"
            );
            ExitCode::FAILURE
        }
    }
}

struct CliOptions {
    config: SimulationConfig,
    output: Option<PathBuf>,
    database: Option<PathBuf>,
    revision: Option<String>,
    policy: GoalPolicy,
}

fn run() -> Result<(), String> {
    let options = parse_options()?;
    if let (Some(output), Some(database)) = (&options.output, &options.database) {
        validate_destinations(output, database)?;
    }
    if options.output.is_some() || options.database.is_some() {
        let destination = options
            .output
            .as_ref()
            .map(|path| path.to_string_lossy().into_owned())
            .unwrap_or_else(|| format!("sqlite:{}", options.database.as_ref().unwrap().display()));
        let mut logged_run =
            Simulation::new_logged_with_policy(options.config, destination, options.policy)?
                .run_logged();
        if let Some(revision) = options.revision {
            logged_run.events[0].details["code_revision"] = revision.into();
        }
        if let Some(database) = options.database {
            let key = save_run(&database, &logged_run.events)?;
            eprintln!("saved Run {key} to {}", database.display());
        }
        if let Some(output) = options.output {
            write_jsonl(&output, &logged_run.events)?;
        }
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

fn validate_destinations(output: &Path, database: &Path) -> Result<(), String> {
    // Resolve directory/symlink aliases before either destination is written.
    fn resolved(path: &Path) -> Result<PathBuf, String> {
        if path.exists() || path.symlink_metadata().is_ok() {
            return path.canonicalize().map_err(|error| error.to_string());
        }
        let parent = path
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .unwrap_or(Path::new("."));
        create_dir_all(parent).map_err(|error| error.to_string())?;
        Ok(parent
            .canonicalize()
            .map_err(|error| error.to_string())?
            .join(path.file_name().ok_or("invalid output path")?))
    }
    let output_resolved = resolved(output)?;
    for base in [database.to_path_buf(), resolved(database)?] {
        for suffix in ["", "-wal", "-shm"] {
            let mut protected = base.as_os_str().to_os_string();
            protected.push(suffix);
            let protected = PathBuf::from(protected);
            if output_resolved == resolved(&protected)?
                || (output.exists()
                    && protected.exists()
                    && same_file::is_same_file(output, &protected).map_err(|e| e.to_string())?)
            {
                return Err("--output must not overwrite the database or its WAL/SHM files".into());
            }
        }
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
    let mut database = None;
    let mut revision = None;
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
            "--db" => database = Some(PathBuf::from(value)),
            "--revision" => revision = Some(value),
            _ => return Err(format!("unknown argument: {argument}")),
        }
    }
    let mut policy = GoalPolicy::preset(config.strategy);
    policy.enemy_weight = weights[0].unwrap_or(policy.enemy_weight);
    policy.item_weight = weights[1].unwrap_or(policy.item_weight);
    policy.stairs_weight = weights[2].unwrap_or(policy.stairs_weight);
    policy.temperature = weights[3].unwrap_or(policy.temperature);
    if revision
        .as_ref()
        .is_some_and(|value| value.trim().is_empty())
    {
        return Err("--revision must not be empty".into());
    }
    if revision.is_some() && output.is_none() && database.is_none() {
        return Err("--revision requires --db or --output".into());
    }
    for path in [output.as_ref(), database.as_ref()].into_iter().flatten() {
        if path.as_os_str().is_empty() {
            return Err("output/database path must not be empty".into());
        }
    }
    if output.is_some() && output == database {
        return Err("--db and --output must use different paths".into());
    }
    Ok(CliOptions {
        config: config.validate()?,
        policy: policy.validate()?,
        output,
        database,
        revision,
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
