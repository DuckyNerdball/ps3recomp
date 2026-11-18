# Monster Madness soak / fuzz harness

PowerShell tooling for the Monster Madness: Grave Danger (BLUS30140) port. It was written for one machine's layout:
the game data folder is `E:\Projects\MonsterDigger` and the project is `E:\Projects\ps3recomp\templates\project`.
Edit the paths at the top of each script for any other layout. None of these scripts contain or produce anything to
commit. Logs, frame dumps and LS dumps stay in the data folder.

| script | what it does |
|---|---|
| `common_run.ps1 -tag X -secs N` | One unattended run. It kills any running game first, runs muted (MM_VOLUME=0), and logs to `logs\X.out.txt` / `logs\X.err.txt`. |
| `verify_run.ps1 -tag X -secs N [-set "K=V;K2=V2"] [-pad <autopad>]` | A build_rel run with the speed/audio defaults. Clears known debug switches first. |
| `soak.ps1 -seeds 1,2,.. -secs 300 -skipIntro -noBuild -batch NAME [-extraEnv "K=V;.."]` | Fuzzed runs (MM_AUTOPAD_FUZZ=seed) that reach gameplay and bucket each run: hang:&lt;lr&gt;, stall, low_fps, high_silence, strobe, new log signatures. Writes one CSV row per run to `logs\soak\results.csv`. Per-seed logs and frames go to `logs\soak\<seed>\`. |
| `soak_summary.ps1 -batches A[,B]` | Bucket rates, gameplay fps avg/p5, worst 5 s window, longest frame, silence: the latest run per seed across the named batches. |
| `hang_hunt.ps1` | Repeated short boots until the pre-title REF hang (main thread at lr 0x0016FBE4) shows up with the `[REFWAIT]` probe. |
| `fmod_bisect.ps1`, `fmod_bisect2.ps1` | Bisect which lifted FMOD ph1 range stalls the game: interpreted ranges via `MM_FMOD_SKIP`. They need a local guard hook in the generated (uncommitted) FMOD lift, which the current regenerated lift no longer has. They are kept as a method reference. |

Comparing batches: run the same seeds before and after a change, plus fresh ones. A change counts only if its bucket's
rate drops and no other bucket grows (`docs\NOTES.md` in the data folder has the before/after tables).
