use serde::{Deserialize, Deserializer, Serialize, Serializer};

#[derive(Debug, Clone, PartialEq, Default)]
pub struct TimelineMetrics {
    fields: serde_json::Map<String, serde_json::Value>,
}

impl TimelineMetrics {
    pub fn empty() -> Self {
        Self::default()
    }

    pub fn from_value(value: serde_json::Value) -> Self {
        match value {
            serde_json::Value::Object(fields) => Self { fields },
            _ => Self::empty(),
        }
    }

    pub fn into_value(self) -> serde_json::Value {
        serde_json::Value::Object(self.fields)
    }

    pub fn as_object(&self) -> &serde_json::Map<String, serde_json::Value> {
        &self.fields
    }

    pub fn as_object_mut(&mut self) -> &mut serde_json::Map<String, serde_json::Value> {
        &mut self.fields
    }
}

impl From<serde_json::Value> for TimelineMetrics {
    fn from(value: serde_json::Value) -> Self {
        Self::from_value(value)
    }
}

impl Serialize for TimelineMetrics {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        self.fields.serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for TimelineMetrics {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        Ok(Self::from_value(serde_json::Value::deserialize(
            deserializer,
        )?))
    }
}
