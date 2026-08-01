mod inspect;
mod model;

pub use inspect::{
    InspectLimits, OpaqueResource, PackageError, PackageInspection, ResourceRecord,
    ValidatedPackage, inspect_path, inspect_path_with_limits,
};
pub use model::*;

#[cfg(test)]
mod tests;
