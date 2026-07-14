# Repository instructions

This repository implements the design in `docs/` for a security-sensitive macOS app.

Current status: the personal-use Phases 0 through 3 are implemented, tested, and installed.
Read `docs/VERIFICATION_2026-07-14.md` before changing lifecycle or privileged behavior.

Before editing code, read these files in order:

1. `docs/HANDOFF_5_5.md`
2. `docs/DESIGN.md`
3. `docs/SECURITY.md`
4. `docs/IMPLEMENTATION_PLAN.md`
5. `docs/ACCEPTANCE_TESTS.md`

Follow the implementation phases in order. Do not run `sudo`, install a LaunchAgent, write to
`/Library` or `/etc/sudoers.d`, or install a package until the user has explicitly reviewed and
approved the Phase 3 installation step.

The bundle ID and helper paths must use the `com.github.oonishidaichi.capsomnia` namespace.
The sudoers filename is `capsomnia_oonishidaichi` because sudo ignores includedir filenames that
contain a period. The app must not use networking, telemetry, Input Monitoring, a shell, or
arbitrary helper arguments. Keep the upstream MIT license and attribution when upstream code is
reused.

If implementation pressure conflicts with the security design, stop and report the conflict
instead of silently weakening the boundary.
