# Spec driven workshop

Build the same app a third time, now spec driven with Spec Kit: first a constitution, then a spec, a plan and tasks, and only then the code.

Keep [cheatsheet.md](./cheatsheet.md) open next to the chat: the install, the commands in order and what to read after each one.

## Install Spec Kit

Spec Kit needs uv, the Python package manager. The setup script in this folder checks uv, offers to install it when it is missing, and installs the Spec Kit CLI at the version the workshop uses:

- **Windows:** double-click `setup.cmd`.
- **macOS, Linux or Git Bash:** run `./setup.sh`.

If you already have uv, you can install it yourself instead:

```bash
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v1.1.3 --force
```

Then make your project in the folder where it should live:

```bash
specify init my-app --integration copilot
```

Open the new `my-app` folder in VS Code and open Copilot Chat in agent mode.

## The steps

Your agent shows the commands as `/speckit.plan` or `/speckit-plan`; both are the same command.

1. `/speckit.constitution`: the hard rules of your project. Write it together with your neighbours. Start with three rules, for example: fictional data only, plain HTML and JavaScript without a build step, every feature works with the keyboard.
2. `/speckit.specify` followed by your first prompt from the vibecoding rounds. Say what and why, not which technology.
3. `/speckit.clarify`: answer the questions yourself, do not say "you decide".
4. `/speckit.plan` followed by your technical choices.
5. `/speckit.tasks`
6. `/speckit.implement`

## Read before you run

Every generated file is a gate. Read `spec.md` before the plan, `plan.md` before the tasks, `tasks.md` before you implement. Find one assumption the agent made in `spec.md` and decide whether you agree.

## Rules

- Fictional data only. No customer data and no personal data in a prompt.

## Afterwards

Compare your three versions of the same app: vibecoded, grilled, and spec driven. What changed, and why?
