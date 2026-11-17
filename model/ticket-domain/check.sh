#!/bin/sh
# The model's checks: its scenarios, the walk over `step` against
# `modelInvariant`, and the finalizer's walk against its invariants, which
# must also reach every witness in that same run. The seeds are pinned so one
# tree has one verdict; pass SEED to walk elsewhere. A violation prints the
# seed that reproduces it; run that without --verbosity for the trace.
set -eu
cd "$(dirname "$0")"

model=ticket_tests.qnt
seed=${SEED:-0x1}

quint test "$model"
quint run --seed="$seed" --max-steps=25 --max-samples=400 --verbosity=1 \
	--invariant=modelInvariant "$model"

out=$(quint run "$model" --seed="$seed" --max-steps=25 --max-samples=400 \
	--verbosity=1 --init=initFinalizing --step=finalizerStep \
	--invariants modelInvariant evolveClosed evolveOnlyWhatDecideProduces \
	resumeKeepsTheOperation neverStuck \
	--witnesses someThirdRound someFailedBasis someWithdrawnBasis \
	somePassedLaterRound someLaterCycleFinalization \
	someDoneAfterReevaluation someRevokedFromFinalization 2>&1) || {
	printf '%s\n' "$out" >&2
	exit 1
}
printf '%s\n' "$out"

reached=$(printf '%s\n' "$out" | grep -c ' was witnessed in ' || true)
if [ "$reached" -ne 7 ]; then
	echo "check: the finalizer's walk reported $reached witnesses, not 7" >&2
	exit 1
fi
if printf '%s\n' "$out" | grep ' was witnessed in 0 trace' >&2; then
	echo "check: the finalizer's walk never reached a witness" >&2
	exit 1
fi
