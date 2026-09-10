# Weekly notes triage

Runs as a cloud routine, Sunday evening, with no one at the keyboard. Nothing here may wait on an
answer.

The notes store is reached through the `memory` MCP tools. It is one markdown space, one folder per
project. Read `index.md` for the layout, `Library/Tasks` for the task model, and this repo's
`CLAUDE.md` for the rules on where a fact belongs — the clone is the authority on those, not your
own judgement.

## What you may write

- **Create** exactly one new note: `Inbox/triage-<YYYY-MM-DD>.md`.
- **Move** ticked tasks and executed specs, as described under Archive below.
- **Nothing else.** Do not edit a note's body, do not delete an Inbox capture, do not refile a
  capture. Filing is Arthur's decision — `index.md` says so: *"Nothing moves your notes on its
  own."* Propose, and let him move it.

## 1. Inbox

For each note under `Inbox/` (ignore any `triage-*` from a previous run):

- Say what it is in one line.
- If its destination is unambiguous under the rules in `CLAUDE.md` and `index.md`, name it.
- If it is genuinely Arthur's call, write a **question** with two or three concrete options. That
  is the normal outcome for anything personal, anything spanning two projects, and anything that
  might be a task rather than a note.
- Say how old it is. A capture older than two weeks is worth flagging on its own.

## 2. Archive

Perform these; they are mechanical and the work is already done.

- **Ticked tasks.** Any `- [x]` on a project's `tasks` page moves to that project's
  `tasks-archive`, newest month first, under a `## YYYY-MM` heading. Each entry keeps its topic
  tag and gains a short line saying **what actually closed it** — source that from `git log` in
  this clone, or from the linked spec. If you cannot source it, say `Closed; the tick date was not
  recorded.` rather than inventing a reason. If the project has no `tasks-archive`, create one
  with the same preamble `dotfiles/tasks-archive` uses.
- **Executed specs.** A spec under `<project>/specs/` whose task you just archived moves to
  `<project>/specs/archive/`.
- **Solved problems.** Do **not** collapse these yourself. A solved problem leaves state behind,
  and `CLAUDE.md` requires extracting the config to the host page and the rulings to "Ruled out"
  *before* it becomes one line in `problems-passed`. List candidates in the triage note as a
  proposal and stop there.

## 3. Priorities for next week

Read the one board, `tasks.md`, and every project's `tasks` page.

- Group the open tasks by stage. Say how many are in each.
- Name every `#next` item that is blocked on **a decision Arthur has not made**, as opposed to work
  not yet done. That distinction is the useful output here; the task line's own "why not yet"
  clause is where it is stated.
- Propose stage moves — a `#next` that has sat untouched for a month probably wants `#someday`; a
  `#someday` whose blocker has cleared probably wants `#next`. Propose, do not retag.
- If nothing is `#now`, say so plainly and suggest the one candidate.

## 4. Send it

Post a short digest to Telegram over the Bot API:

```
curl -sS -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
  --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
  --data-urlencode "parse_mode=Markdown" \
  --data-urlencode "text=<your digest>"
```

Keep it under about 15 lines: the counts, the open questions in full, and one line naming the
triage note. The questions are the reason the message exists — put them in the message, not only
in the note.

If either variable is unset, skip the send and put `Telegram not configured; digest not sent.` at
the top of the triage note. Do not fail the run over it.

You cannot read Arthur's reply. His answer arrives in a terminal session, not here, so never write
as though waiting on one.
