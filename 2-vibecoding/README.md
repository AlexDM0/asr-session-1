# Vibecoding workshop, round 2: grill me

Build the same app as in round 1, with the same first prompt. The only difference: this repository contains the grill-me skill, so the agent interviews you before it builds.

## How to work

1. Open this folder in VS Code. Do not reuse your round 1 folder: the agent should not see your first attempt.
2. Open Copilot Chat in agent mode. If a chat from round 1 is still open, type `/clear` to start an empty one.
3. Paste your first prompt from round 1, and add: "Use the grill-me skill before you build anything."
4. Answer the agent's questions. Every question comes with its recommendation; accept it or choose differently.
5. When the questions are done, let it build. Run it and try it.

## The skill

The skill lives in `.github/skills/grill-me/SKILL.md`. Open it: a skill is just a folder with a markdown file that tells the agent when to use it and what to do.

## Rules

- Fictional data only. No customer data and no personal data in a prompt.

## Afterwards

Compare round 1 and round 2. Did you see a difference? Why do you think that is?
