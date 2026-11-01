# Other members' modules

These Flutter features were written against the same Oracle schema but
belong to other members of the team, so they are not part of this app:

| Folder     | Module                              | Tables                          |
|------------|-------------------------------------|---------------------------------|
| `bookings` | Member 3 — the booking engine       | BOOKING                         |
| `ledger`   | Member 4 — escrow and the ledger    | CREDIT_TXN, CREDIT_POLICY       |
| `admin`    | Member 5 — feedback and disputes    | FEEDBACK, DISPUTE, ADMIN        |

They sit outside `lib/`, so Flutter does not compile them and they do
not appear in this build. The code is kept rather than deleted because
the schema, the package and the SQL files still cover all five modules —
only the screens are scoped.

**This app covers Member 1 (onboarding and profiles) and Member 2
(skills and availability).**
