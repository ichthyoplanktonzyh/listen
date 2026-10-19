//! Inspect a Content Package v3 carrier and report qualification.

use std::path::PathBuf;

use content_package::v3::{V3Inspection, inspect_v3_path};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args_os()
        .nth(1)
        .ok_or_else(|| "usage: inspect-package <package-path>".to_owned())?;
    let inspection = inspect_v3_path(PathBuf::from(path))?;
    println!("OK {}", summarize(&inspection));
    Ok(())
}

fn summarize(inspection: &V3Inspection) -> String {
    let mut parts = vec![format!("resources={}", inspection.resources.len())];
    if let Some(first) = inspection.resources.first() {
        let kind = &first.entry.descriptor.kind;
        parts.push(format!("first_kind={}", kind));
    }
    parts.join(" ")
}
