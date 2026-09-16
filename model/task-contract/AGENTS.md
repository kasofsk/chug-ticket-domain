# Shared task contract

This directory owns the immutable vocabulary shared by ticket Work,
Evaluation, and Execution. It is a shared kernel, not an independently
persisted task aggregate.

- Keep task terminals neutral: produced, process failed, or execution
  unavailable. Pass/fail and lifecycle progression belong to the owning
  protocol.
- Keep logical task identity stable across provider-specific retries. Owners create
  identities; Execution only carries them.
- Construct validated results from the obligation and its result contract so
  callers cannot provide identities or contract claims that disagree.
- Store the task definition, authoritative provenance, and immutable artifact
  references. Derive owner identity and other deterministic values instead of
  copying them into sibling fields.
- Finalization is not a task and cancellation is an owner instruction, not a
  task terminal.

`task.qnt` is the executable contract model. Keep it and `README.md` consistent
with any implementation change that alters the shared vocabulary.
