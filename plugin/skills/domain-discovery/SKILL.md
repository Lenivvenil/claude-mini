---
name: domain-discovery
description: Explore a new or unclear bounded context with the owner, DDD and Event Storming style. Use for "event storming", "new bounded context", "исследуем домен", "нужна Ubiquitous Language". Interviews the owner, then has domain-researcher draft the overview. Not for small changes inside an existing context (use plan).
---

# Domain discovery skill

## Steps

1. Name the context and its purpose in one sentence. If the owner describes a change inside an existing context, suggest `plan` instead and update its overview there.
2. Interview the owner through five lenses, one at a time. Stop a lens when answers stop adding anything new.
   - **Actors.** Who or what interacts with the context: people, services, schedulers, external systems.
   - **Events and the storm around them.** What has happened that matters, in past tense. Then the commands that cause them, the policies ("when X, then Y"), the aggregates that guard invariants, the read models, and the hotspots.
   - **Boundary.** What is in and what is out. Which term changes meaning across the edge. If none does, question whether this is a separate context.
   - **Ubiquitous language.** Core terms defined in business words, with aliases to avoid.
   - **Context map.** For each neighbouring context, the relationship as a DDD pattern. Explain the patterns briefly if the owner does not know them.
3. Keep the owner's words. Whatever stays unanswered is a hotspot, not a guess.
4. Pass the interview notes to the `claude-mini:domain-researcher` agent. It writes the overview where the project keeps domain docs and returns open questions.
5. Show the owner the path and the open questions. Suggest `claude-mini:domain-reviewer` on the result.

## Output

The overview path from domain-researcher, and the open questions for the owner.

## Hard rules

- Do NOT design implementation: no tables, APIs or code.
- Do NOT answer for the owner. An unknown is recorded as a hotspot.
