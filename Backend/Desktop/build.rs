fn main() {
    tauri_build::build();
    // Tauri writes editor schemas beside the manifest; keep generated files in build/.
    let manifest = std::path::PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let source = manifest.join("gen/schemas");
    if source.is_dir() {
        let destination = manifest.join("../../build/Backend/TauriSchemas");
        std::fs::create_dir_all(&destination).expect("create Tauri schema output directory");
        for entry in std::fs::read_dir(&source).expect("read generated Tauri schemas") {
            let entry = entry.expect("read Tauri schema entry");
            if entry.file_type().expect("read Tauri schema type").is_file() {
                std::fs::rename(entry.path(), destination.join(entry.file_name()))
                    .expect("move generated Tauri schema");
            }
        }
        let _ = std::fs::remove_dir(&source);
        let _ = std::fs::remove_dir(manifest.join("gen"));
    }
}
