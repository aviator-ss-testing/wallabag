# Driving the Wallabag preview

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
