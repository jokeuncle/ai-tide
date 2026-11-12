# v0.1.0 preview verification

Observed on 2026-11-12, macOS 26.4.1, Apple Silicon. This is a bounded local preview acceptance, not a claim of all-platform or complete traffic coverage.

| Check | Evidence / result |
| --- | --- |
| Core regressions | `swift run tide-tests`: 9 groups, 0 failures. Malformed counters, reordered columns and quoted names, duplicate PID, wrong signer, unverified code, PID reuse, executable changes, baseline, elapsed time, counter reset and gaps. |
| Controlled real transport | A local TCP sender transferred 2,097,152 bytes. Production `NettopParser` read exactly 2,097,152 additional received bytes on the receiving process. No provider request involved. |
| Native Claude Code request | A persistent streaming CLI session returned `TIDE_OK`. Exact running PID was observed in 22 samples with identifier `com.anthropic.claude-code`, team `Q6L2SF6YDW`, and nonzero system byte counters. |
| Native Codex CLI request | An independent CLI execution returned `TIDE_OK`. Exact PID was observed in 12 samples with identifier `codex`, team `2DC432GLL2`, and nonzero counters. |
| Existing Codex GUI | Signed `com.openai.codex.helper` processes had actual byte increments; App-owned CLI ancestry was separately observed. This does not identify a specific request or conversation. |
| TUI | A real interactive Codex TUI was started and its signed CLI process enumerated. A model turn completed; its response window was not reliably correlated with nonzero traffic samples. CLI execution and TUI share the same supported binary identity, but the interactive turn is not counted as a successful traffic-specific acceptance. |
| Actual UI | The running native application showed original jade/copper artwork and actual Codex rates. User-reported missing artwork and blue segmented controls were corrected and recaptured. |
| Independent native review | Reviewer requested a menu-bar collection-state/source caption fix. The source was updated to show initialization/error/pause and per-client baseline/missing states, with `nettop · 含本地连接 · 非 token` coverage. |

The first fast-request attempt exposed a polling limitation: request success alone did not prove capture. A version-number Claude executable also exposed a basename-prefilter omission. Discovery now examines code identities regardless of install path/name; unrelated signatures are briefly cached, while accepted identities are rechecked around every reading. A later persistent-session test separately proved signed identity and traffic observations.

Raw process-path JSONL stays local and is gitignored. Shareable numerical evidence is in `evidence/controlled-transfer.json` and `evidence/real-clients-summary.json`. Packaged resources, icon, Universal slices, relocated launch and DMG integrity are checked by the release workflow; final package observations are recorded in the GitHub release notes.

Unverified: Intel physical hardware; clean-machine browser quarantine/Gatekeeper first approval; independent ChatGPT chat-client build; browsers, remote SSH internals, legacy Node-hosted clients, complete short-lived process/flow capture, and network/provider combinations beyond the observed machine. Signed identity is not proof of request semantics. No payloads, tokens or model thinking are inferred.
