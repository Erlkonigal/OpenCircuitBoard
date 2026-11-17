#![allow(non_snake_case)]
use ocb_core::{
    CompileInput,
    Project::{self, ProjectDocument},
    Session::{Action, Session},
};
use std::{
    path::PathBuf,
    sync::{Arc, Mutex},
};
use tauri::{
    Manager, State,
    ipc::{InvokeBody, Request, Response},
};
struct Services {
    Simulation: Arc<Session>,
    Settings: PathBuf,
    Recent: Mutex<Vec<String>>,
}
fn recent(services: &Services, path: &str) -> Result<(), String> {
    let mut paths = services.Recent.lock().map_err(|_| "SettingsUnavailable")?;
    paths.retain(|p| p != path);
    paths.insert(0, path.into());
    paths.truncate(8);
    let temp = services.Settings.with_extension("tmp");
    std::fs::write(
        &temp,
        serde_json::to_vec(&*paths).map_err(|_| "SettingsInvalid")?,
    )
    .map_err(|e| e.to_string())?;
    std::fs::rename(temp, &services.Settings).map_err(|e| e.to_string())
}
#[tauri::command]
fn recentProjects(services: State<'_, Services>) -> Vec<String> {
    services
        .Recent
        .lock()
        .map(|v| v.clone())
        .unwrap_or_default()
}
#[tauri::command]
async fn openProject(
    path: String,
    services: State<'_, Services>,
) -> Result<ProjectDocument, String> {
    let file = PathBuf::from(&path);
    let board = tauri::async_runtime::spawn_blocking(move || Project::load(&file))
        .await
        .map_err(|e| e.to_string())??;
    recent(&services, &path)?;
    Ok(board)
}
#[tauri::command]
async fn saveProject(
    path: String,
    project: ProjectDocument,
    services: State<'_, Services>,
) -> Result<String, String> {
    let path =
        tauri::async_runtime::spawn_blocking(move || Project::save(&PathBuf::from(path), &project))
            .await
            .map_err(|e| e.to_string())??
            .to_string_lossy()
            .into_owned();
    recent(&services, &path)?;
    Ok(path)
}
fn rawInput(bytes: &[u8]) -> Result<(CompileInput, (i32, i32)), String> {
    if bytes.len() < 24 || bytes.len() % 4 != 0 {
        return Err("SimulationInputInvalid".into());
    }
    let read = |i: usize| i32::from_le_bytes(bytes[i..i + 4].try_into().unwrap());
    if read(0) != 0x4f434249 || read(4) != 4 {
        return Err("SimulationInputInvalid".into());
    }
    let width = read(8);
    let height = read(12);
    if width <= 0 || height <= 0 {
        return Err("SimulationInputInvalid".into());
    }
    let count = (width as usize)
        .checked_mul(height as usize)
        .filter(|&n| n <= ocb_core::Simulation::MaximumCellCount)
        .ok_or("SimulationGridTooLarge")?;
    if read(16).checked_add(width - 1).is_none() || read(20).checked_add(height - 1).is_none() {
        return Err("SimulationInputInvalid".into());
    }
    if bytes.len() != 24 + count * 32 {
        return Err("SimulationInputInvalid".into());
    }
    let array = |start: usize| {
        (0..count)
            .map(|i| read(24 + (start * count + i) * 4))
            .collect()
    };
    Ok((
        CompileInput {
            Width: width as usize,
            Height: height as usize,
            Kinds: array(0),
            InitialStates: array(1),
            ClockHoldTicks: array(2),
            ComponentIds: array(3),
            Directions: array(4),
            FixedDrives: array(5),
            DefaultValues: array(6),
            CrossMasks: array(7),
        },
        (read(16), read(20)),
    ))
}
#[tauri::command]
async fn compileGrid(
    request: Request<'_>,
    services: State<'_, Services>,
) -> Result<Response, String> {
    let InvokeBody::Raw(bytes) = request.body() else {
        return Err("SimulationInputInvalid".into());
    };
    let (input, origin) = rawInput(bytes)?;
    let worker = services.Simulation.clone();
    tauri::async_runtime::spawn_blocking(move || worker.request(Action::Compile(input, origin)))
        .await
        .map_err(|e| e.to_string())?
        .map(Response::new)
}
#[tauri::command]
async fn simulationCommand(
    action: String,
    session: u32,
    value: f64,
    services: State<'_, Services>,
) -> Result<Response, String> {
    let action = match action.as_str() {
        "poll" => Action::Poll(session, value as u32),
        "run" => Action::Run(session, value),
        "pause" => Action::Pause(session),
        "step" => Action::Step(session, value as i32),
        "seek" => Action::Seek(session, value as u64),
        "toggle" => Action::Toggle(session, value as usize),
        "reset" => Action::Reset(session),
        "release" => Action::Release,
        _ => return Err("SimulationCommandInvalid".into()),
    };
    let worker = services.Simulation.clone();
    tauri::async_runtime::spawn_blocking(move || worker.request(action))
        .await
        .map_err(|e| e.to_string())?
        .map(Response::new)
}
#[tauri::command]
async fn inspectCell(
    session: u32,
    cell: usize,
    services: State<'_, Services>,
) -> Result<Response, String> {
    let worker = services.Simulation.clone();
    tauri::async_runtime::spawn_blocking(move || worker.request(Action::Inspect(session, cell)))
        .await
        .map_err(|e| e.to_string())?
        .map(Response::new)
}
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let directory = app.path().app_data_dir()?;
            std::fs::create_dir_all(&directory)?;
            let settings = directory.join("RecentProjects.json");
            let paths = std::fs::read(&settings)
                .ok()
                .and_then(|data| serde_json::from_slice::<Vec<String>>(&data).ok())
                .unwrap_or_default();
            app.manage(Services {
                Simulation: Arc::new(Session::default()),
                Settings: settings,
                Recent: Mutex::new(paths),
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            recentProjects,
            openProject,
            saveProject,
            compileGrid,
            simulationCommand,
            inspectCell
        ])
        .run(tauri::generate_context!())
        .expect("OpenCircuitBoard desktop runtime");
}
