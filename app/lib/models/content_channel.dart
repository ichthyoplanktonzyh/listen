/// The four content channels a learner can be in. Exactly one owns the
/// immersive stage at a time; listening is the resting state.
///
/// Lives in `models/` rather than beside the switcher widget because the
/// channel machinery (see `ContentChannelCoordinator`) is domain logic that
/// must not depend on the widget layer.
enum ContentChannel { listening, reading, speaking, writing }
