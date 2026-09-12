## Model Delegation & Subagents
* When spawning subagents or delegating tasks, always inherit the current active model (such as Sol) from the parent session r
ather than falling back to default system models.
* Ensure all background worker loops and sub-tasks execute using the user's selected provider model.

