# /intelliwhisper-install

Install or update IntelliWhisper by building it from source on this machine.
This command handles both fresh installs and updates — it is safe to run repeatedly.

## Steps

1. **Check prerequisites**
   - Run `xcode-select -p` to verify Xcode Command Line Tools are installed.
     If the command fails, tell the user to run `xcode-select --install` and stop.
   - Run `sw_vers -productVersion` and warn if the result is below 14.0.
   - Run `git --version` as a sanity check.

2. **Determine repo location**
   - Check whether the current working directory already contains the IntelliWhisper
     repository by looking for a `Package.swift` whose first line contains `swift-tools-version`
     and a `Sources/IntelliWhisper` directory. If both exist, use the cwd as the repo
     path and skip cloning — just run `git pull` to update.
   - Otherwise, ask the user where they want to clone the repository.
     Suggest `~/Developer/IntelliWhisper` as the default.
     Accept any path the user provides.

3. **Clone or update**
   - Fresh clone: `git clone https://github.com/AOTE-Holding/IntelliWhisper.git <chosen-path>`
   - Existing repo: `cd <repo-path> && git pull`

4. **Build**
   - Run: `cd <repo-path> && ./scripts/build.sh --release --pkg`
   - This takes 1–3 minutes on first run (compiles Swift + downloads dependencies).
     Stream the output so the user can see progress.
   - If the build fails, show the error and stop. Do not proceed to install.

5. **Install**
   - Run: `open <repo-path>/.build/IntelliWhisper.pkg`
   - Tell the user: click **Continue → Install** in the installer window.
     The app will launch automatically when the installer finishes.

6. **Hand off**
   - Inform the user that the setup wizard will guide them through:
     microphone, Input Monitoring, Screen Recording, and Accessibility permissions;
     hotkey configuration; Whisper model download; and optional Ollama setup.
   - If this was an **update** (IntelliWhisper was already installed), warn the user
     that macOS permissions are reset on every install and the wizard will ask them
     to re-grant all permissions. This is expected — it takes about a minute.
   - Nothing more is needed from this command.
