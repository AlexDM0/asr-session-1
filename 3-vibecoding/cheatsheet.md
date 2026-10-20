# Getting started cheatsheet

## Install and set up

| Step | Do |
|---|---|
| Install Spec Kit | Windows: double-click `setup.cmd`. macOS, Linux or Git Bash: `./setup.sh` |
| Or, with uv already installed | `uv python install 3.13 --default`, then `uv tool install --force specify-cli --python 3.13 --from https://github.com/github/spec-kit/archive/refs/tags/v1.1.3.zip` |
| Set up this folder (the setup script does this) | `specify init . --integration copilot --script py --force` |
| Open it | Open this folder in VS Code, then Copilot Chat in agent mode |

## The commands, in order

Your agent shows them as `/speckit.plan` or `/speckit-plan`; both are the same command.

| Command | What you type after it | What it writes | Read before the next step |
|---|---|---|---|
| `/speckit.constitution` | Your project's hard rules | `.specify/memory/constitution.md` | The rules: are they yours? |
| `/speckit.specify` | Your first prompt from the vibecoding rounds: what and why, no technology | `specs/001-<name>/spec.md` | Find one assumption the agent made |
| `/speckit.clarify` | Nothing; answer its questions yourself | Answers in `spec.md` | Did your answers land in the spec? |
| `/speckit.plan` | Your technical choices | `plan.md` and its companions in the same folder | Does the plan follow the constitution? |
| `/speckit.tasks` | Nothing | `tasks.md` | Are the tasks small and in a sensible order? |
| `/speckit.implement` | Nothing | The code | Run it and try it |

## Starter rules for the constitution

- Fictional data only.
- Plain HTML and JavaScript, no build step.
- Every feature works with the keyboard.

## Tips

- Technology goes in `/speckit.plan`, never in `/speckit.specify`.
- Never answer a clarify question with "you decide".
- Not happy with a file? Change it, or run the command again with more detail, before you move on.
- Compare at the end: vibecoded, grilled and spec driven. What changed, and why?
