# TimeBank — Flutter front end

Peer tutoring credit exchange. Clean architecture, Bloc, black theme.

---

## How this reaches Oracle

**Flutter cannot use JDBC.** JDBC is a Java API and there is no Oracle
driver for Dart, so a Dart program has no way to open an Oracle
connection. The architecture is therefore three tiers:

```
Flutter app  ──HTTP/JSON──►  Spring Boot  ──JDBC──►  Oracle
  (this)                      (../api)               (../sql)
```

The JDBC work is real and graded — it lives in `../api`, which uses the
same DAO classes as the console app. This project is the presentation
half.

---

## Running it

**1. Oracle must be up and seeded.** See `../README.md`.

**2. Start the API:**

```bash
cd ../api
mvn spring-boot:run
```

It listens on `0.0.0.0:8081`. Check it:

```bash
curl http://localhost:8081/api/ledger/audit
```

**3. Run the app:**

```bash
flutter pub get
flutter run
```

### The one thing that catches people out

Inside an Android emulator, `localhost` means *the emulator itself*, not
your computer. `ApiClient.defaultBaseUrl` already handles this:

| Where the app runs | Base URL |
|---|---|
| Android emulator | `http://10.0.2.2:8081` |
| iOS simulator, desktop, web | `http://localhost:8081` |
| **A real phone** | `http://<your-computer-LAN-ip>:8081` |

For a real phone, pass it in:

```dart
await initDependencies(baseUrl: 'http://192.168.1.14:8081');
```

Both devices must be on the same Wi-Fi.

---

## Layer structure

```
lib/
├── core/
│   ├── theme/          black palette + ThemeData
│   ├── error/          Failure (domain) and Exception (data)
│   ├── network/        dio client, the only place HTTP lives
│   ├── usecase/        the UseCase contract
│   └── di/             get_it wiring
├── features/<name>/
│   ├── domain/         entities, repository INTERFACES, use cases
│   ├── data/           models, datasource, repository IMPLEMENTATION
│   └── presentation/   bloc, pages, widgets
└── shared/widgets/
```

Dependencies point **inward**:

```
presentation  ──►  domain  ◄──  data
```

The domain depends on nothing. That is why `Student`, `Booking` and
`LedgerEntry` contain no `fromJson`, no dio import and no mention of
Oracle — swapping the backend would not touch them.

### Error handling

Repositories return `Either<Failure, T>` rather than throwing. The
compiler then refuses to let a Bloc read the success value without
having written the failure branch:

```dart
emit(result.fold(
  (failure) => StudentFailure(failure.message),
  (students) => StudentsLoaded(students),
));
```

`RuleFailure` carries a message that came from an Oracle trigger —
"Overdraft limit reached", "That slot is already booked on 03-NOV-2026".
Those are shown to the user verbatim, because no wording the app could
invent would be more accurate.

---

## The design

| Token | Value | Used for |
|---|---|---|
| canvas | `#08080A` | page background |
| surface | `#101014` | cards and panels |
| border | `#26262F` | every hairline |
| accent | `#D9A441` | credits, primary actions, selected tab |
| positive / negative | `#4FB477` / `#E0564E` | amounts only |

Three decisions worth knowing:

**Borders, not shadows.** A drop shadow is invisible on black, so
hierarchy comes from hairline borders and one step of surface lightness.

**Credits are brass, not green.** Green would read as "success" on every
balance including a negative one. Brass reads as currency, and leaves
green and red free to mean up and down.

**Tabular figures on every number.** Proportional digits make a column of
balances jitter as values change. `FontFeature.tabularFigures()` gives
every digit the same width, so decimals line up and a list reads like a
ledger.

The design raises its voice in exactly one place: the balance at the top
of the passbook. Everything else stays quiet.

---

## What each screen demonstrates

| Screen | Rubric operation | What it shows about the schema |
|---|---|---|
| Students | Display, Search, Insert, Update | The role badge reads TUTOR / TUTEE / **BOTH** / NOT STARTED — BOTH only exists because the specialization is overlapping, NOT STARTED because it is partial |
| Register | Insert | Student + starter grant written in one transaction |
| Sessions | Display, Insert, Update | Escrow state on every card; only the action the session actually needs next is offered, because the database enforces check-in before confirmation |
| Session code | — | The anti-fraud mechanism: issued to the tutee, typed in by the tutor |
| Passbook | Display | The balance is summed from the rows on screen — nothing stores it |
| Audit | Display | `balances + escrow = granted − penalised`, plus the collusion report |

---

## Not yet run

This code has been written and reviewed but **never compiled** — the
container it was built in has no Flutter SDK. Expect to fix a few things
on the first `flutter run`:

```bash
flutter pub get
flutter analyze      # do this before flutter run
```

Needs **Flutter 3.27 / Dart 3.6 or later**, because the theme uses
`Color.withValues()`. Check with `flutter --version`.
