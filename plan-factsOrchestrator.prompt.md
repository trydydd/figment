**Plan**

Build a Python-based, terminal-first orchestrator that lives on the USB, keeps default runtime state ephemeral, and extends the current Linux launcher model into a privacy-focused coding agent. The recommended shape is: keep the shell launcher thin, move orchestration into a Python runtime on the drive, use a local model-serving layer suitable for tool calling, and preserve strict no-trace defaults with an explicit unsafe debug mode only.

**Steps**
1. Define the runtime contract and on-drive layout.
   Decide where the Python runtime, orchestrator code, prompts, tool schemas, temp/session artifacts, and debug artifacts live on the USB, and how launchers pass mode/model/privacy flags into the orchestrator.

2. Evolve the launcher into a bootstrap layer.
   Preserve the existing responsibilities from [LinuxLaunch.sh](LinuxLaunch.sh) and [BuildYourOwn.sh](BuildYourOwn.sh): hardware detection, binary discovery, RAM-aware model selection, cleanup hooks, and diagnostics. Move agent loop and tool dispatch out of shell and into Python.

3. Replace direct CLI chat with a local inference service layer.
   Plan for a long-lived local model interface, most likely `llama.cpp` server mode or equivalent, so the orchestrator can do multi-step tool calling cleanly instead of one-shot terminal invocation.

4. Define resource-aware modes.
   Keep the current Q4/Q8 auto-selection spirit from [LinuxLaunch.sh](LinuxLaunch.sh), but formalize profiles such as `Lite`, `Standard`, and `Performance` with explicit mappings for model, context budget, timeout, and tool concurrency.

5. Design strict no-trace runtime behavior.
   Default all session state to RAM-backed temp storage when available, add startup/shutdown cleanup, crash cleanup, PID/socket/temp-file wiping, and a panic-wipe path. Debug mode should be explicit, visibly unsafe, and never on by default.

6. Specify the initial tool system and permissions model.
   Initial scope should cover read/list/search files, edit/write files, shell commands, Git operations, and optional network access. Mutating tools should require confirmation in v1, with path allowlists, symlink traversal protection, command restrictions, and timeouts.

7. Design the agent loop and tool schema format.
   Define how the model sees available tools, emits structured tool-call intents, receives tool results, retries, and summarizes in terminal. Keep compatibility with the “skills.md standard” requirement by shaping tool descriptions and metadata consistently.

8. Define the terminal-first UX.
   Keep CLI as the only v1 UI. Plan startup banners, mode display, confirmation prompts, error output, unsupported-tool handling, and degraded-mode messaging so the agent still feels like a more sophisticated successor to [LinuxLaunch.sh](LinuxLaunch.sh).

9. Add Linux lifecycle handling.
   Cover process groups, signal traps, temp-dir lifecycle, USB path resolution, permissions fixes, and behavior when models or binaries are missing or incompatible.

10. Stage containment and safety.
   Start with path sandboxing, tool allowlists, process timeouts, and resource limits. Defer stronger container-grade isolation until the Linux implementation is proven.

11. Run decision spikes before implementation.
   Test Python-on-USB packaging size, local model-serving latency, Qwen3 structured tool-call reliability, and Linux cleanup behavior before committing to the full orchestrator build.

12. Update documentation in parallel.
   Extend [README.md](README.md), [USB_SETUP_README.md](USB_SETUP_README.md), and [MEMORY.md](MEMORY.md) so build, run, privacy guarantees, debug mode, and troubleshooting stay aligned with the actual architecture.

**Relevant Files**
- [LinuxLaunch.sh](LinuxLaunch.sh): current Linux launcher behavior to preserve and refine.
- [BuildYourOwn.sh](BuildYourOwn.sh): USB bootstrap flow, model/binary acquisition, and current portability logic.
- [README.md](README.md): product philosophy, hardware expectations, and user-facing behavior.
- [USB_SETUP_README.md](USB_SETUP_README.md): terminal-first setup workflow to extend.
- [MEMORY.md](MEMORY.md): prior troubleshooting and design decisions.

**Verification**
1. Confirm the launcher/runtime split before implementation starts.
2. Validate `Lite`/`Standard`/`Performance` profiles against the current RAM-based model-selection behavior.
3. Review startup, runtime, crash, and shutdown flows specifically for no-trace guarantees.
4. Validate tool safety rules: path allowlists, confirmation gates, command restrictions, and network-default-off behavior.
5. Run short spikes for Python packaging size, local server latency, structured tool-call reliability, and cleanup reliability.
6. Verify docs match the real bootstrap and runtime flow.

**Decisions**
- Runtime for v1: Python on the USB.
- Primary UI for v1: terminal CLI.
- Initial tool scope: read/list/search files, edit/write files, run shell commands, Git operations, optional network access.
- Privacy default: strict no-trace mode, with optional explicit debug mode only.
- Current implementation scope: Linux-only.
- Product direction: evolve the current launcher-based USB runtime, not replace it.

**Further Considerations**
1. Python packaging approach still needs a final implementation choice.
Recommendation: ship a self-contained Python runtime on the USB rather than relying on host Python.

2. Mutating tool UX needs a hard rule before implementation.
Recommendation: require explicit confirmation for file edits, shell execution, Git writes, and network use in v1.

3. Inference transport still needs a final choice.
Recommendation: prefer a local server/API mode over wrapping one-shot CLI execution, because it fits multi-step orchestration better.
