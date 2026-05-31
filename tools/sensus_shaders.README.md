# sensus_shaders.g.json

This JSON is the output of sensus-core's `examples/dump_shaders.rs` and is
vendored here as the input for the shader sync codegen (#12). **Do not
hand-edit.**

## Top-level shape (freshness metadata)

```json
{
  "schema": "sensus-shader-dump/v1",
  "sensus_core_version": "0.5.0",
  "shaders": [ { "name", "glsl", "layout" }, ... ]
}
```

- `schema` — output format id. `generate_shaders.dart` rejects an unknown
  schema (bump it on incompatible shape changes).
- `sensus_core_version` — the `sensus-core` crate version this dump was produced
  from. `generate_shaders.dart` asserts its **major** matches the `sensus-core`
  dependency in `rust/Cargo.toml` (`sensus-core = "0.5"`), so a stale vendored
  dump fails loudly instead of silently generating against the wrong version.

Each `shaders[]` entry is `{ "name", "glsl", "layout" }`:

- `name` — snake_case shader stem (matches `shaders/<name>.frag`).
- `glsl` — the GLSL ES 3.00 source from sensus-core `*_glsl()`.
- `layout` — the `setFloat`-ordered scalar uniform names, derived from the
  source declaration order. `vec2 uXxx` is split into `uXxx_x`, `uXxx_y`;
  `uMatrix[9]` is expanded to `uMatrix0`..`uMatrix8`; a synthetic
  `uResolution_x`, `uResolution_y` pair is appended (the Impeller shader derives
  UV from `FlutterFragCoord()` / resolution because Impeller has no `vTexCoord`
  varying).

## Scope

Only filters whose uniform model matches the ue host wiring
(`lib/rendering/shader_filter.dart`) are dumped: a single `uTexture` sampler and
scalar `float` / `vec2` uniforms. Filters that need a second sampler
(`floaters`/`uMask`, `depth_aware_blur`/`uDepth`), `int`/`uint` uniforms
(`glaucoma`, `cataract`, `flickering_stars`, `metamorphopsia`), or per-frame
`uTime` (`vertigo`, `bppv_rotation`) are intentionally excluded until the host
gains the matching support.

`dry_eye` and `starbursts` are also excluded: their GLSL loops compare the index
against a runtime value (`radius`, `iRayLen`/`numRays`), which the Impeller SkSL
backend rejects ("loop index must be compared with a constant expression"). They
need a sensus-side rewrite to constant loop bounds first.

This yields **20** generated shaders.

## Regenerating (when sensus shaders change)

The sensus repo lives at `/home/ariori/repos/2026/sensus` (published crate
`sensus-core = "0.5"`):

```sh
cd /home/ariori/repos/2026/sensus
cargo run -p sensus-core --example dump_shaders \
    > /path/to/universal-experience/tools/sensus_shaders.g.json
```

**Verify the version stamp matches the dependency** (else the next codegen run
will fail the major-version assert):

```sh
# both should agree on the major (0.5.x):
grep sensus_core_version tools/sensus_shaders.g.json
grep '^sensus-core' rust/Cargo.toml
```

If sensus's major changed, bump `rust/Cargo.toml`'s `sensus-core` constraint and
`_expectedSensusMajor` in `tools/generate_shaders.dart` together.

Then regenerate the `.frag` files and `pubspec.yaml` shaders block:

```sh
cd /path/to/universal-experience
dart run tools/generate_shaders.dart
```

The CLI also prints the included (20) vs intentionally-excluded filters (with
the reason for each) to stderr, so the scope gap is never silent.

`dart run tools/generate_shaders.dart --check` verifies the committed
`shaders/*.frag` and `pubspec.yaml` are in sync with this JSON (used by
`test/shader_codegen_test.dart`); it exits non-zero on drift.
