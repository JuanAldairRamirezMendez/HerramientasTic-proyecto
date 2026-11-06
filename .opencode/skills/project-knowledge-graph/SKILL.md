---
name: Project Knowledge Graph
description: Use for any question about this project's codebase, architecture, dependencies, or documentation. Explains where the Graphify knowledge graph lives and how to query it before falling back to grep.
---

# Project Knowledge Graph

This repository has a persistent Graphify knowledge graph. Treat it as the first
source of truth for codebase questions.

## Location

```text
/home/aldair/Proyectos/HerramientasTic-proyecto/graphify-out/
├── graph.json        # raw graph: nodes, edges, communities
├── GRAPH_REPORT.md   # audit report: god nodes, communities, surprises
└── graph.html        # interactive visualization
```

The graph covers the root repo plus both submodules:

- `Gestor-Inteligente-de-Documentos/` — backend (Express + TypeScript)
- `Gestor-Inteligente-de-Documentos-Frontend/` — frontend (React + Vite)

## Query before searching

When `graphify-out/graph.json` exists, answer from the graph first:

```bash
graphify query "<question>"
graphify path "<node A>" "<node B>"
graphify explain "<concept>"
```

If the CLI is unavailable, traverse `graphify-out/graph.json` directly with
NetworkX or a small Python script. Prefer scoped subgraphs over reading the
whole report or grepping the entire repository.

## When to read the report

Read `graphify-out/GRAPH_REPORT.md` only when:

- the query/path/explain commands do not surface enough context,
- you need a broad architecture review,
- or you need the community map, god nodes, or surprising connections.

Do not paste the whole report into chat. Extract only the relevant section.

## Keeping the graph current

After modifying code, run:

```bash
graphify update .
```

`update` is AST-only and costs no API tokens. If documentation, papers, or images
changed, a full semantic rebuild may be needed:

```bash
graphify .
```

Without an LLM key, `graphify .` refuses to process non-code files. In that case,
use `graphify . --code-only` for code, or run the semantic extraction with the
host agent as described in the installed `graphify` skill.

Set `GEMINI_API_KEY` or `GOOGLE_API_KEY` to let Graphify use Gemini for semantic
extraction automatically.

## Known limitations

- The graph can contain dangling or collapsed edges after incremental updates.
  Treat it as a map, not as a formal proof; verify critical claims in source.
- Generated graph files may be dirty; that is expected.
- Do not skip Graphify merely because `graphify-out/` is dirty. Skip it only when
  the task is specifically about stale or incorrect graph output, or when the
  user asks you not to use it.

## Relationship to other docs

- `graphify-out/GRAPH_REPORT.md` — generated architecture audit.
- Root `AGENTS.md` and submodule `AGENTS.md` — operational rules for agents.
- `PROJECT_CONTEXT.md` and `docs/` — curated human documentation. If they
  disagree with the graph, prefer the curated docs for intent and the graph for
  current structure.
