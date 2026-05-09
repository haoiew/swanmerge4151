# Contributing

Contributions are welcome when they stay within the scope of this repository: building, running, documenting, and validating the SWAN merge-only workflow.

## Scope

Good contributions include:

- fixes to the `make merge` build path;
- portability improvements for wrapper scripts;
- documentation improvements for dependency setup and NetCDF validation;
- minimal source fixes that affect merge-only behavior.

Out-of-scope changes include:

- broad SWAN physics changes;
- unrelated model setup examples;
- private data, private paths, or unpublished case files;
- generated build outputs, logs, or merged NetCDF files.

## Before opening a pull request

Please check:

1. No private paths, user names, tokens, or unpublished case names are included.
2. Generated files such as `*.o`, `*.mod`, `*.exe`, `PRINT*`, `Errfile*`, logs, and NetCDF outputs are not committed.
3. Any SWAN source change preserves existing license headers.
4. Documentation makes clear whether a path is an example placeholder or a user-provided path.

## Testing

This repository does not include a public SWAN benchmark case. Test changes with your own SWAN MPI fragments and document what was checked, including whether important NetCDF variables contain valid values.
