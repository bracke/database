# External process and power-loss crash harness

`Database.Crash_Harness` implements the external crash harness.

The design has two processes:

1. The parent process calls `Run_External_Crash` or
   `Run_All_External_Crashes`.
2. The child process calls `Database.Crash_Harness.Child_Main`, writes real
   durable artifacts, and terminates with `OS_Exit` at the crash boundary.

The parent never trusts the child result alone.  It validates the generated
artifacts using the database/WAL/page/backup/encryption validation paths.

## Crash modes

- `Process_Before_WAL_Commit`
- `Process_After_WAL_Commit`
- `Process_During_Checkpoint`
- `Power_Loss_Torn_Page`
- `Power_Loss_Torn_WAL_Frame`
- `Power_Loss_Truncated_Encrypted_Page`
- `Power_Loss_Partial_Backup_Manifest`

## Guarantees checked

- Uncommitted WAL frames are not replayed.
- Committed WAL frames survive child process death.
- Torn page writes are rejected safely.
- Torn WAL frames are rejected safely.
- Truncated encrypted artifacts fail authentication.
- Partial backup manifests fail parsing/validation.
- Missing child executables do not create false-positive test success.

## Build

```sh
alr exec -- gprbuild -P tests/tests.gpr
alr exec -- gprbuild -P tests/database_tests.gpr
```

The normal AUnit binary may call
`Database.Testing.Verify_External_Process_Power_Loss_Crash` with the path to the
child executable.

## Limitations

This harness models process death and power-loss artifacts; it does not claim to
control real disk cache, controller, or filesystem ordering behavior.  Those
belong in platform-specific destructive/system tests.  The engine-level contract
validated here is that all generated partial artifacts fail closed or converge
through normal recovery.
