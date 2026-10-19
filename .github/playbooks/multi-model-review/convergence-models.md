# Multi-model review - Convergence

Every multi-reviewer panel uses unanimous convergence. Each reviewer must return the success verdict for the same independently computed artifact id, with no unaddressed blocking findings. A prior READY verdict does not carry forward across a changed artifact.

For a new round, reuse the same idle reviewer agents through `write_agent` and provide the changed paths and delta. Reviewers re-read the target and compute its artifact id at both the start and end of the review. Relaunch only when a reviewer is gone or unresponsive, using the same registry tier or the one sanctioned Grok-to-codex fallback. There is no round cap or follow-up cap.

The caller records findings and routes them through the C2 status enum. A non-unanimous round is not a pass, regardless of whether dissent is blocking or advisory.

## Output

The convergence result is returned to `procedure.md` and recorded in the per-round evidence output. Only a unanimous result for the final artifact is `CONVERGED`.
