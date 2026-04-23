# LLM Stick

**Offline, uncensored, zero-log AI on a Linux flash drive.**

No internet. No installation. No accounts. Plug in, double-click, ask anything.

This project is derived from and inspired by the original [OSE FACTS project](https://github.com/WEAREOSE/facts), which served as the source, starting point, and inspiration for this work.

I've stripped Windows and Mac support to reduce scope for features that are in-flight. For those operating systems check the original project.

---

## What Is This?

This is the complete, open-source build for the **LLM Stick** AI flash drive. Everything you need to build your own is right here — the launcher scripts, the guide files, and the folder structure. 

## Quick Start

### Build Your Own

1. Get a USB flash drive (16GB minimum, 32GB+ recommended)
2. Format it as exFAT
3. Clone or download this repo onto the drive
4. Run the setup script:

   ```bash
   ./BuildYourOwn.sh --target /path/to/usb/mount
   ```

5. Or manually download the required binaries into the `.system/` folder (see below)
6. Run `LinuxLaunch.sh`

### Required Downloads (Not Included)

| File | Size | Source |
|------|------|--------|
| `llamafile` | ~293MB | [llamafile v0.9.3](https://github.com/Mozilla-Ocho/llamafile/releases/download/0.9.3/llamafile-0.9.3) (rename to `llamafile` if needed) |
| `Qwen3-4B-Instruct-2507-abliterated.Q8_0.gguf` | ~4.0GB | [HuggingFace](https://huggingface.co/prithivMLmods/Qwen3-4B-2507-abliterated-GGUF/tree/main/Qwen3-4B-Instruct-2507-abliterated-GGUF) |
| `Qwen3-4B-Instruct-2507-abliterated.Q4_K_M.gguf` | ~2.3GB | [HuggingFace](https://huggingface.co/prithivMLmods/Qwen3-4B-2507-abliterated-GGUF/tree/main/Qwen3-4B-Instruct-2507-abliterated-GGUF) |

## Hardware Requirements

| | Minimum | Recommended |
|---|---------|-------------|
| **RAM** | 8GB | 16GB+ |
| **Linux** | Any modern x86_64 or ARM64 | NVIDIA GPU for acceleration |
| **Drive** | USB 2.0 works | USB 3.0 for faster load times |

## How It Works

1. Plug in the drive
2. Run `LinuxLaunch.sh`
3. The launcher kills any ghost processes from previous sessions
4. All chat history is wiped (zero-log privacy — nothing is ever saved)
5. Your RAM is detected and the best model is selected:
   - 16GB+ → Q8 (high quality)
   - 8-15GB → Q4 (efficiency mode)
6. GPU is detected (NVIDIA on Linux)
7. Model loads into memory (10-60 seconds)
8. `>` prompt appears — start asking questions

## What's In the Box

```
LLM Stick/
├── LinuxLaunch.sh              # Linux launcher
├── LICENSES/
│   ├── LLAMA_CPP_LICENSE.txt   # MIT License (llama.cpp)
│   └── MODEL LICENSES/
│       └── QWEN_LICENSE.txt    # Apache 2.0 (Qwen)
└── .system/                    # Hidden folder
   ├── llamafile               # Linux engine binary
    ├── *.Q8_0.gguf             # High performance model (~4GB)
    └── *.Q4_K_M.gguf           # Efficiency model (~2.3GB)
```

## Troubleshooting

### Linux
| Problem | Fix |
|---------|-----|
| "Permission denied" | `chmod +x /path/to/drive/.system/llamafile` |
| Hangs forever | Check `free -m` — need 4GB+ available. Close browsers. |
| Slow performance | Normal without NVIDIA GPU. CPU inference works but is slower. |

- **AI crashes mid-conversation:** Context window full. Close and relaunch.
- **AI refuses to answer:** Close and relaunch. Rephrase the question.

## Tech Stack

| Component | Technology | License |
|-----------|-----------|---------|
| AI Engine (Linux) | [llamafile v0.9.3](https://github.com/Mozilla-Ocho/llamafile/releases/tag/0.9.3) | MIT |
| Model | [Qwen3-4B-Instruct abliterated](https://huggingface.co/prithivMLmods/Qwen3-4B-Instruct-2507-abliterated-GGUF) | Apache 2.0 |
| Context Window | 8192 tokens | — |

## Support

This is offered AS-IS, and you are responsible for your own support.