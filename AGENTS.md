# Agent instructions

This repository is an Ada 2022 relational storage engine.

## Toolchain

Use Alire GNAT 15 only. Do not run plain system `gnat*`, `gnatmake`, `gnatls`,
`gnatprove`, `gprbuild`, `gnatdoc`, or `gprinstall` in this workspace. Use
`alr exec -- ...` for compiler, prover, documentation, installer, and builder
commands so PATH cannot select a different GNAT installation.

The root, tests, and `database_inspect` manifests must pin:

```toml
[[depends-on]]
gnat_native = "=15.2.1"
```

Confirm the selected compiler with:

```sh
alr exec -- gnatls --version
```

## Validation

Preferred validation:

```sh
alr exec -- gprbuild -P tools/tools.gpr
tools/bin/check_all
```

When GNAT/GPRBuild/GNATprove are unavailable through Alire, state that clearly
and run the static checks the environment supports.

## Boundaries

Project-local tooling uses sibling `../project_tools`; cryptographic primitives
come from sibling `../cryptolib`. Do not introduce system GNAT/GPR toolchain
dependencies.
