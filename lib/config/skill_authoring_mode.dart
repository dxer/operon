/// What the AI skill author should produce.
///
/// Instruction skills are the mobile default: the model writes a prompt and
/// the browser agent resolves elements at runtime. Flow skills are the
/// advanced path and contain recorded, replayable steps.
enum SkillAuthoringMode { instruction, flow }
