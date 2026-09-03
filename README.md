# state_forms
OK State Reporting forms plugin for PowerSchool

## Project Review

This plugin currently implements one form — the Oklahoma ED 506 (Indian Student
Eligibility Certification) — as a read-only, server-rendered PowerSchool page. It has
no data-entry or save path: every value is pulled from fields the district already
populates elsewhere (`U_Tps_Indian_Education`, `U_StudentsUserFields`, the `Tribal
Names` codeset and its `U_TRIBAL_HQ_ADDRESS` extension). The page must render correctly
both standalone and inside PowerSchool's "mass print student screens" feature, which
does not execute page JavaScript — so the whole form has to resolve server-side through
PowerSchool tag syntax alone.

### Components

**`src/WEB_ROOT/admin/studentlist/counselor/aet_massprint.ok_state_forms.content.footer.txt`**
Content-footer hook for the base AET Mass Print Student Screen plugin. Injects an
`<option>` into mass print's page-selection dropdown so "Ed 506 Form" is one of the
screens a counselor can add to a batch, gated behind
`~[if.~(studentscreenaccess;quicklookup.html)=1]` so it only appears for users with
access to the underlying page.

**`src/WEB_ROOT/admin/students/ok_state_forms/ed_506_form.html`**
The form itself — a single HTML file, no separate elements/partial file and no
JavaScript, since mass print only ever executes the final rendered markup. All dynamic
content resolves through three PowerSchool access patterns, used according to what
actually works on this server:
- plain page-level DATs (`~([Table]field)`) for `Students` and native one-to-one
  extensions like `U_StudentsUserFields`;
- one `tlist_sql` block for everything that touches a codeset or codeset-extension
  table (`CODESET`, `U_TRIBAL_HQ_ADDRESS`) and for `U_Tps_Indian_Education`, none of
  which resolve via `DirectTable.Select`/DAT on this server;
- a second, minimal `tlist_sql` for the one remaining `U_Tps_Indian_Education` value
  (`ED506_Date`) needed outside that block.

Two hard constraints on `tlist_sql` shaped this file and are worth knowing before
touching it: its `~( )` body references bind to the SELECT list **by position**, not by
name, and `~[if]` and DATs (including `*contact_info`) do **not** evaluate inside a
`tlist_sql` body — only bare `~(column_alias)` values from that block's own query do.
See `[[tlist-sql-positional-binding]]` and `[[tlist-sql-reserved-characters]]` in
project memory for the full detail, including the reserved-character (`CHR()`)
requirement for brackets, carets and colons embedded in the SQL.

The print stylesheet in this file was also tuned to fix blank/spillover pages under
mass print: `.box-round`'s forced `page-break-inside: avoid` was removed (it was
pushing a whole tall form to a fresh page rather than letting it split, producing blank
pages before it), and the guardian Address/City/State/Zip fields were resized — Address
widened and given a smaller font so a full street address reliably renders on one line
instead of wrapping to 2–3 lines and pushing the form's total height past a full page.

**`src/WEB_ROOT/images`**
Static assets (`oksde_logo.png`, `checkbox.png`, `checkedbox.png`) carried over from an
earlier iteration of the form. `checkbox.png`/`checkedbox.png` are not referenced by
the current `ed_506_form.html` — the form now draws its radio buttons with plain CSS
(`input[type="radio"]` styling) rather than image swaps — and are candidates for
removal if no other page in this plugin ends up using them.

**`src/WEB_ROOT/pagecataloging/state_forms_nav.json`**
PowerSchool page-cataloging manifest. Adds an "OK State Forms" entry under the Student
Compliance nav section with one child, "Ed 506 Form", linking to
`/admin/students/ok_state_forms/ed_506_form.html?frn=~(studentfrn)` — this is the
standalone (non-mass-print) entry point into the form from a student's record.

### Build & packaging

`make plugin` (via `Makefile`) zips `src/WEB_ROOT` and `src/plugin.xml` into
`dist/<name>-v<version>.zip`, reading the plugin name from `plugin.xml`'s `name`
attribute and its version from the `version` attribute — bump `version` in
`src/plugin.xml` before packaging a release.

### Known open items

- `tribal_member` on `U_Tps_Indian_Education` carries values (`Mother`, `Father`,
  `Student`, `Grandmother`, `Grandfather`, `Sister`, `Self Support`, `Other`, …) that
  don't map to the form's three radio options (`Child`/`Child's Parent`/`Child's
  Grandparent`) — roughly 600 records. No mapping decision has been made for these yet.
- The PPTX slide-8 rule (deriving the proof-of-membership bubble from roll-number
  presence) has not been implemented.

---

## Tribal Names Codeset & U_TRIBAL_HQ_ADDRESS

Technical reference for the codeset/extension pair that drives the tribe name, address,
and federal/state recognition status on the ED 506 form.

### 1. Schema

#### CODESET (`CODETYPE = 'Tribal Names'`)
Standard PowerSchool codeset table (`PS.CODESET`). One row per federally/state
recognized tribe.

- 649 rows, `CODESETID` range 97132–101174 (not contiguous — PowerSchool assigns ids;
  a new code cannot be created with a chosen id).
- `DESCRIPTION` — the tribe's full legal name, e.g. `The Muscogee (Creek) Nation`,
  `Cherokee Nation`. This is the value shown to the district and matched against.
- `CODE`, `DISPLAYVALUE` — standard codeset fields, not used by the form.
- One entry, `Unknown` (codesetid `101174`), was added as a placeholder for stored
  values that name no real tribe (garbage entries, "N/A", etc.).

#### U_TRIBAL_HQ_ADDRESS (codeset extension on `Tribal Names`)
Custom table, one row per codeset entry, joined 1:1 via `CODESETCODESETID`.

| Column              | Type          | Notes                                   |
|---------------------|---------------|------------------------------------------|
| CODESETCODESETID    | NUMBER (19,0) | PK / FK to `CODESET.CODESETID`, not null |
| STREET              | VARCHAR2(800) |                                          |
| LINE_TWO            | VARCHAR2(800) | present, unused by the form              |
| CITY                | VARCHAR2(800) |                                          |
| STATE               | VARCHAR2(56)  | full state name, not abbreviation        |
| POSTAL_CODE         | VARCHAR2(56)  |                                          |
| TRIBE_STATUS        | VARCHAR2(160) | `Federal`, `State`, or blank             |
| WHOCREATED/WHENCREATED/WHOMODIFIED/WHENMODIFIED | — | standard extension audit columns, auto-populated |

Access pattern: `~[DirectTable.Select]` and page-level DATs (`~([Table]field)`) do **not**
resolve against codeset or codeset-extension tables on this server. The form reads this
table exclusively through a `tlist_sql` block that joins it in from Oracle directly — see
`[[tlist-sql-reserved-characters]]` and `[[tlist-sql-positional-binding]]` in the project
memory for the syntax rules that made that block work.

#### U_StudentsUserFields.TPS_TRIBAL_NAMES_CODESET_ID
`VARCHAR2(4000)`, one-to-one Students extension. Holds the codesetid(s) resolved for a
student, `" : "`-delimited when a student has more than one tribe (616 students).
A colon was chosen as the delimiter because it needs no escaping in a regex, in
JavaScript, or in PowerSchool tag syntax. The ED 506 form takes only the first id via
`substr`/`instr` in SQL (see the tlist_sql block in `ed_506_form.html`) — it does not
attempt to display multiple tribes.

### 2. Import process

Both loads went through PowerSchool's **Quick Import**, which requires headers to be
the fully-qualified `TABLE.FIELD` name — a bare field name shows as "auto-matched" in
the UI but the server maps nothing ("You must map at least one column before you are
able to proceed"). Quick Import also required LF line endings on this server; CRLF
files silently failed to import.

#### a. U_TRIBAL_HQ_ADDRESS (`scripts/build_tribal_hq_load.py`)
Source: the existing `tps_tribal_info_json` wildcard data (`.claude/tps_tribal_info_json.txt`),
which already carried codesetid, address, and status per tribe.

1. Parse the wildcard's JS array literal as JSON, dropping its metadata record.
2. Fix two known source misspellings (`Louisana` → `Louisiana`, `New Jesrsey` → `New Jersey`).
3. Emit tab-delimited rows keyed by `CodesetCodesetID`, LF line endings, header row using
   fully-qualified column names.
4. Loaded via Quick Import → 649 tribes.

#### b. U_StudentsUserFields.TPS_TRIBAL_NAMES_CODESET_ID (`scripts/build_codesetid_import.py`)
Source: each student's stored tribe text in `U_Tps_Indian_Education`
(`tps_natamer_tribes`, plus up to three "extra" fields `tribes1/2/3` used when a
student has more than one tribe on file).

1. Build a resolver (`resolve()`) that tries, in order: an exact normalized-string match
   against `CODESET.DESCRIPTION`; a substring/containment match; then an all-tokens-present
   match (stopwords like "tribe", "nation", "band", "of" stripped). Two hardcoded district
   rulings are applied first (`CHEROKEE` → Cherokee Nation `97397`, `CREEK` → The Muscogee
   (Creek) Nation `97410`) since those bare words would otherwise be ambiguous.
2. Anything the resolver can't pin to exactly one codesetid is deferred to a human decision
   (§3) rather than guessed.
3. For a student with multiple tribe fields, resolved ids are de-duplicated (the extra
   `tribes1/2/3` fields very often just repeat the main tribe under a different spelling)
   and joined with `" : "`.
4. Output: tab-delimited, `Students.Student_Number` + the codesetid field, LF line
   endings.
5. Loaded via Quick Import → 15,384 students.

### 3. Data cleanup specification

The stored tribe text predates the codeset and was free-typed/select-list text, so it
does not line up with `CODESET.DESCRIPTION` cleanly. Two supporting artifacts were
built to make every non-obvious mapping decision explicit and reviewable before import,
rather than resolved by fuzzy-match guesswork:

#### tribal_mapping.csv (`scripts/build_tribal_mapping.py`)
Maps the *old select-list options* (`tps_indian_education_tribe_options`, the values a
user could have picked from the on-page dropdown before this rewrite) onto
`CODESET.DESCRIPTION`, for reference/spot-checking, not for driving the import directly.
Each row carries a confidence score (100 = exact normalized match, down through
"truncated at '('" / "state qualifier dropped" variants, to fuzzy `difflib` matches
flagged `REVIEW`) and the match method, so low-confidence rows can be reviewed by a
human before anything downstream trusts them. Fuzzy matching alone was explicitly
rejected as unsafe here — e.g. `Fort Sill Apache Tribe of Oklahoma` is 0.84 similar to
`Apache Tribe of Oklahoma`, a different tribe.

Normalization folds: `&` → `and`, two-letter state abbreviations → full state names,
punctuation stripped, a leading `The` optionally dropped, and everything after the
first `(` or last `,` optionally dropped (to match a description that added a
parenthetical or a state qualifier the option text lacked).

#### tribal_name_questions.csv (`scripts/build_tribal_questions.py`)
One row per **student** whose stored tribe text did not resolve to exactly one codeset
entry automatically. For each, every plausible candidate tribe is listed
(`candidate_1`, `candidate_2`, …, each `codesetid | description`), ranked so Oklahoma
tribes (the district is in Tulsa) and codeset entries starting with `The` sort first.
Column G (`chosen_codesetid`) is where the district records its decision — nothing in
this file is auto-applied to the import.

Key cleanup steps handled here:
- **PascalCase un-collapsing**: the original data-entry page stripped spaces from the
  select value before storing it (e.g. `NavajoNationArizonaNewMexicoUtah`), so a
  `decamel()` step reinserts word boundaries before any matching is attempted.
- **Token-based matching with stopwords**: `of/the/and/tribe/tribes/nation/band/
  indians/indian` are excluded from the comparison so e.g. `Cheyenne-Arapaho` still
  matches `Cheyenne and Arapaho Tribes, Oklahoma`.
- **`Unknown` placeholder**: since PowerSchool assigns codesetids and none could be
  pre-chosen for a new `Unknown` code, decisions in column G that should map to
  "no real tribe" were written as `999999` and swapped for the real codesetid
  (`101174`) once that code existed in the codeset, by `build_codesetid_import.py`
  (`UNKNOWN_CODESETID`).
- **Decision scope**: a ruling is keyed by `(student_number, source_field)` so a
  decision made for a student's `tribes1` value doesn't leak onto their main tribe
  field, but a ruling on a *stored text value* is also generalized to every other
  student who has that exact same stored text (`DECIDED_BY_VALUE`) — except where two
  different students' rows ruled the same text two different ways, in which case that
  value is left ungeneralized and reported.

### 4. How the ED 506 form consumes this

The form's single `tlist_sql` block (in `ed_506_form.html`) does, in one query:

1. Pull the student's `TPS_TRIBAL_NAMES_CODESET_ID`, take the first `:`-delimited id
   (`substr`/`instr`, with the colon passed as `chr(58)` — literal reserved characters
   silently break the tag).
2. Join `CODESET` on that id to get the tribe's `DESCRIPTION`.
3. Left join `U_TRIBAL_HQ_ADDRESS` on `CODESETCODESETID` for street/city/state/zip and
   `TRIBE_STATUS` (rendered as pre-checked `Federal`/`State` recognition radios via
   `DECODE`, since `~[if]` does not evaluate inside a `tlist_sql` body).
4. Left join `U_Tps_Indian_Education` for the remaining ED 506 fields (proof of
   membership, ED506_Date, etc.) — DirectTable.Select/DAT access to that table does not
   resolve on this server, so everything from it is pulled the same way.

Everything referenced in the page body after the `~[tlist_sql;...]` tag must be a bare
`~(column_alias)` bound **by position** to the SELECT list, not by name — see
`[[tlist-sql-positional-binding]]`.
