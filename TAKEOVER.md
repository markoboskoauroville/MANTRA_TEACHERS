# MANTRA_TEACHERS: the Swift code of the two Teacher apps

Public code-only repository (13.11.2026) holding the source of "Ableton Teacher (Mantra)" and "DaVinci Teacher (Mantra)":
one Swift source in app/, built into two bundles by build.sh, on GitHub by .github/workflows/build.yml (release Latest, two zips).
Each app listens on a localhost door; ports are claimed in ~/.config/mantra-ports.json: ableton-teacher 8970, davinci-teacher 8971,
universal-teacher 8972 (not 8965, which is MPA Lessons Analyzer). The lessons, voice files, Oracle scripts, teacher.py and history are in the
private data repository ABLETON_TEACHER; this repository has only the app code. Source of truth for edits: change here, copy teacher.py side there.

## State at close, 13.11.2026

13.11.2026: teacher apps have Swift source and a workflow (GitHub compiles).
