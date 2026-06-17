---
description: How to drive the Wallabag preview app — what it is, getting around (routes, layout), and what's observable as evidence.
---

# Driving the Wallabag preview

Wallabag is a self-hosted "read it later" / bookmarking app. The preview serves
the full web UI at the preview URL. Everything past the login screen requires
authentication — see the `verify-auth` skill for the sign-in flow.

## Getting around

- The main view is a list of saved articles ("entries"), rendered as cards.
- The top toolbar has the page title, a search control, and view-mode toggles
  (list vs. grid).
- Each card links to a reader view and carries per-entry actions (archive,
  star, delete) plus any tags.
- Useful routes: `/` or `/unread/list` (unread), `/starred/list`,
  `/archive/list`, `/config` (settings).

## What's observable here

This is a real running app driven through the browser, so UI state, computed
styles, DOM structure, and console output are all fair game for evidence.
Background jobs and outbound email/integrations are not exercised in the
preview, so don't try to verify anything that depends on them.
