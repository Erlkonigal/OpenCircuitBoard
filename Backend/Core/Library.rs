#![allow(non_snake_case, non_upper_case_globals)]
#[path = "Project.rs"]
pub mod Project;
#[path = "Session.rs"]
pub mod Session;
#[path = "Simulation.rs"]
pub mod Simulation;
pub use Simulation::{CompileError, CompileInput, SimulationCore};

#[path = "RuntimeArena.rs"]
mod RuntimeArena;

#[path = "GraphLocalityOrderer.rs"]
mod GraphLocalityOrderer;
