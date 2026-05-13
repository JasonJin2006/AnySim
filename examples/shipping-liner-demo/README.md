# Shipping Liner Demo

This folder is an example AnySim project package.

It shows how a user-facing project keeps its modeling assets together while relying on installed platform extensions:

- `DEVS` provides the solver/runtime.
- `Shipping` provides the domain library, preset builder, views, KPIs, and optimization scaffolding.

## Layout

- `anysim-project.json`: project manifest
- `data/`: project-bound input data references or copied inputs
- `scenarios/`: scenario-level config overrides
- `docs/`: project notes and modeling assumptions

## Run

From the repo root:

```powershell
julia bin/anysim-server.jl --project examples/shipping-liner-demo
```

The server will load the project manifest, resolve the `shipping-single-vessel` preset, and apply the first scenario config by default.

## First Milestone

The first packaged milestone is `AEU3` single-vessel baseline validation:

- one route
- one vessel
- schedule-driven arrival/departure events
- port statistics suitable for later KPI and export work

## Research Track

The project now also contains an academic-oriented research framework under:

- `docs/shipping-research-framework.md`

That framework defines the intended direction beyond the current DEVS shipping demo:

- normalized shipping input modeling
- time-space network optimization scaffolding
- MILP specification and LP export support
- execution-plan bridging between optimization and simulation
- disturbance-aware simulation for robustness evaluation
