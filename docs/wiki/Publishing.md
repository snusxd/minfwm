# Publishing the Wiki

`.github/workflows/wiki.yml` syncs Markdown pages from `docs/wiki/` to the
repository's GitHub Wiki after changes land on `main`. It also supports manual
runs. Wiki pages are kept flat in `docs/wiki/` so each source filename maps to
one Wiki page. Removed source pages are removed from the Wiki; non-Markdown Wiki
files are preserved.

Before the first run, enable the repository Wiki and create its initial page.
Add an Actions secret named `WIKI_TOKEN` with permission to write to that Wiki.
The workflow needs this secret because the Wiki is stored in a separate Git
repository. Changes pushed by the workflow do not trigger another workflow run.
