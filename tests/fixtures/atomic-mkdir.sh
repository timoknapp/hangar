#!/usr/bin/env bash
# Exclusive directory creation for synthetic GitHub-ref/WIP reservations.
# Some mkdir implementations report success when a racing creator already made
# the directory. Use the syscall result, not a CLI's post-error directory check.
# Source this file; callers supply one disposable fixture path.
fixture_claim_directory() {
  python3 -c 'import os, sys; os.mkdir(sys.argv[1])' "$1" 2>/dev/null
}
