# 0013. "Run as administrator" means Wine's admin token, never macOS sudo

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** Utsav, Claude

## Context
Users asked for installers to "run with admin/sudo privileges" to get past "access denied". On Windows
that's UAC elevation. Under Wine, "access denied" has different causes:

1. **The installer demands an elevated token.** Wine gives processes a *limited* token
   (`TokenElevationTypeLimited`, `TokenIsElevated=0`). It elevates only when the exe's manifest requests
   `requireAdministrator`/`highestAvailable` (ntdll `needs_elevation` → `elevate_token`), or when it's
   launched with the `runas` verb (shell32 `get_admin_token`). Installers that check for admin without
   declaring it fail. Measured on both runtimes: plain launch gives type 3 (limited), `runas` gives
   type 2 (full).
2. **macOS gets in the way of the installer's files:** quarantine flags, privacy-protected folders
   (Downloads/Desktop/Documents), and read-only disk images whose installers write next to themselves.
3. **Read-only files in the prefix.** DOS read-only maps to a missing unix `w` bit, and installers that
   overwrite such files get access denied.
4. **Files owned by another user,** almost always left by someone once running `sudo wine`.

Running Wine as root fixes none of 1–3: Wine has no Windows ACLs for root to bypass. It *causes* 4 for
every file it touches, Wine refuses to use a prefix it doesn't own, and it would hand root to arbitrary
downloaded installers.

## Decision
- `decant run --admin <bottle> <exe> [args]` (the app's "Run as Administrator", on by default for
  installers in Add Game):
  1. refuses if the bottle has foreign-owned files, pointing to `decant repair`;
  2. clears read-only bits in `drive_c`;
  3. stages an installer that lives outside the bottle into `C:\decant-stage\<folder>-<name>`. It uses
     an APFS clone (`cp -c`, instant on the same disk) and strips quarantine. From a shared folder
     (home, Downloads, Desktop, Documents, compared by physical path) only `<stem>*` files are copied
     (`setup.exe`, `setup-1.bin`); from any other folder, including a mounted image, the whole folder;
  4. launches through `share/decant-elevate64.exe`, which calls `ShellExecuteExW` with verb `runas`, waits,
     and returns the exit code.
- `decant repair <bottle>` fixes read-only bits and quarantine without a password. If foreign-owned files
  exist, it prints the **one** command that needs root (`chown -R <user> "<bottle>"`, exit 3), and
  `--print-sudo` emits just that command. The app runs it through macOS's own administrator prompt
  (`osascript … with administrator privileges`). Decant never stores or handles the password.

## Alternatives considered
- **`sudo wine …`:** see Context. It creates the problem it claims to solve, and is a security risk.
- **Windows `__COMPAT_LAYER=RunAsAdmin`:** not implemented by Wine (no references in the 11.0 source).
- **Wine's `runas.exe`:** it's `CreateProcessWithLogonW` for another user, not elevation.
- **Patching every installer's manifest:** invasive, and breaks signed installers.

## Consequences
- Installers that need elevation work without root. Tests check the token in real Wine (`tests/live.sh`).
- Staged copies stay in `C:\decant-stage` (free when APFS-cloned) and are replaced on the next admin run
  of the same installer.
- The only privileged operation in Decant is a user-confirmed `chown` back to the user, shown in full
  before it runs.
- `share/decant-elevate64.exe` is committed prebuilt and rebuilt from source under the same rule as
  the launch shims ([ADR-0007](0007-commit-prebuilt-shims.md)).
