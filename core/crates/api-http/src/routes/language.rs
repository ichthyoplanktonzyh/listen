use crate::{ApiError, ApplicationError, Json, LanguageCode, Path};

pub(crate) async fn list_languages() -> Json<&'static [&'static str]> {
    Json(domain::available_languages())
}

pub(crate) async fn language_profile(
    Path(code): Path<String>,
) -> Result<Json<domain::LanguageLearningProfile>, ApiError> {
    let language = LanguageCode::parse(code).map_err(ApplicationError::from)?;
    Ok(Json(domain::profile_for(&language)))
}
