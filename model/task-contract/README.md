# Shared task contract

Work and Evaluation use the same immutable task obligation and neutral terminal vocabulary. Execution carries the obligation unchanged across physical retries. The owning ticket or evaluation protocol decides what a valid produced result means.

A task definition pins its workload, inputs, execution requirements, and result contract, each as an opaque immutable reference. The execution requirements reference names whatever the scheduler needs to place and authorize the task — capabilities, repository access, destination policy; the contract neither reads nor structures it, and its enforcement belongs to the execution adapter. A task obligation pairs that definition with a logical task identity and one opaque immutable context reference. Work task identity is `(ticket, cycle)`; evaluator task identity adds stage, generation, and evaluator. The context reference is scoped by that identity. The application commits the referenced context bundle with the decision and reuses it for replay and redelivery.

`ValidatedTaskResult` carries the exact obligation and an immutable `resultRef`. The adapter validates the referenced result against the obligation's pinned result contract before producing this value. A produced terminal does not itself mean the work is accepted or an evaluator passed. `TaskProcessFailed` and `TaskExecutionUnavailable` carry the task identity and immutable evidence reference. Cancellation is an owner instruction, not a terminal.

The shared contract contains no repository, Git access, output shape, evaluator verdict, or finalization policy. Authoring and application adapters validate source and destination policy, repository access, result provenance, and the shape of referenced content before submitting a terminal. A result that cannot be validated is reported as a failure or an application recovery condition, never as a produced result.

Finalization has its own operation and result contract because it can perform a conditional mutation. It may use the same physical runner without becoming a task terminal.

## Identity and delivery

The logical identity remains stable across provider attempts. Execution may retry physical delivery without creating a new Work cycle or evaluator generation. It may not synthesize a new task definition or reinterpret a result contract. The producer records the validated immutable result and its obligation together, so downstream code never needs a second task identity or contract claim that might disagree.

The owner creates task identities; Execution only carries them. A Work task derives from ticket and cycle. An evaluator task derives from ticket, work cycle, stage key, stage generation, and evaluator key. The context reference is scoped by that identity: a numeric work cycle reference is not a global content blob ID. The application stores an immutable bundle under the scoped key, makes it available before delivery, and reuses it unchanged on replay.
