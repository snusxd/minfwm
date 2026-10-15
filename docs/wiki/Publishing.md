# Wiki Publishing

The `docs/wiki/` directory in this repository serves as the single source of truth for the project's GitHub Wiki.

---

## How Synchronization Works

A GitHub Actions workflow (`.github/workflows/wiki.yml`) automatically synchronizes all Markdown files from `docs/wiki/*.md` to the official GitHub Wiki whenever changes are merged into the `main` branch.

- **Flat Structure**: Every `.md` file in `docs/wiki/` maps directly to a Wiki page named after the file.
- **Automatic Deletion**: If a file is deleted from `docs/wiki/`, it is automatically removed from the Wiki.
- **Manual Runs**: The workflow can also be triggered manually from the GitHub Actions tab.

---

## Setup Requirements

If configuring the sync workflow for a new repository or fork:

1. **Enable Wiki**: Go to repository **Settings**, enable the **Wikis** feature, and create an initial dummy page.
2. **Access Token**: Add an Actions secret named `WIKI_TOKEN` (a Personal Access Token with repository write permissions), as GitHub Wikis are stored in a separate Git repository.
