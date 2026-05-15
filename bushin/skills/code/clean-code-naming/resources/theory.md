# Clean Code — Naming Theory

Full reasoning behind each principle listed in `../SKILL.md`. Read this when you want the WHY, not the WHAT. For concrete patterns, open `practices.md`.

## T1. Reveal intent

A name answers *why it exists, what it does, how it's used*. If you'd need a comment to explain it, the name failed.

The cost of a longer name is paid once at the keyboard; the cost of an unreadable name is paid every read. Files are read fifty times for every time they're written — name discipline compounds.

## T2. No disinformation

Don't claim a type the value doesn't have — `accountList` that holds a `Set` is a lie. Don't reuse abbreviations already owned by something well-known (`hp` is HP-UX, not "hypotenuse"). Ban `l` and `O` as identifiers — they look like `1` and `0` in most fonts.

Names that differ by one inner word (`...HandlingOfStrings` vs `...StorageOfStrings`) hide bugs in IDE autocomplete: the developer picks one without reading carefully.

## T3. Make meaningful distinctions

Number series (`a1`, `a2`) and noise suffixes (`Info`, `Data`, `Object`, `Variable`) are non-information. If removing them changes nothing, they don't belong.

The classic trap: `getActiveAccount()` / `getActiveAccounts()` / `getActiveAccountInfo()`. The caller can't choose. Replace with distinct verbs that encode intent.

Prefer `source` / `destination` over `a1` / `a2` for parameter roles. Don't misspell to dodge a keyword (`klass` for `class`) — pick a different concept-level name.

## T4. Pronounceable

Programming is a social activity. Names get said aloud in standups, pairing, code review. `genymdhms` walking around as "gen-yah-mudda-hims" is fun until someone explains it to a new hire.

## T5. Searchable. Length tracks scope

Wide-scope variables and constants must be greppable. `7` is impossible to find; `MAX_CLASSES_PER_STUDENT` is one ctrl-F away.

Length is proportional to scope. `i` in a five-line loop is fine. The same `i` as a class field is malpractice.

Worst single-letter choice: `e`. It's the most common letter in English, so it grep-matches every comment and string in the codebase.

## T6. No encodings

No Hungarian (`strName`, `intCount`, `phoneString`). No member prefixes (`m_dsc`, `_field`). Don't decorate interfaces with `I*` — `ShapeFactory`, not `IShapeFactory`. If you must mark the implementation, mark it by specificity (`JpaOrderRepository`), not by `*Impl`.

Modern languages and IDEs encode everything Hungarian was invented to encode. Carrying the legacy adds rename friction and obscures the real concept.

## T7. No mental mapping

The reader shouldn't translate `r` into "lowercased URL without host or scheme". Single-letter loop counters (`i`, `j`, `k`) are tolerated only as tradition. Clarity beats cleverness.

The smart-programmer trap: showing off mental juggling by demanding readers do the same. The professional difference: pros write code others can understand.

## T8. Side effects in the name (Rule N7)

A name must not hide what the function does. `getX()` promises a cheap, idempotent fetch. A `getX()` that constructs `X`, opens a socket, or calls a network endpoint lies to the caller about cost and failure modes.

Either rename to reflect the truth (`getOrCreateX()`) or restructure so the construction is explicit (lazy property, dedicated factory call).

## T9. Match level of abstraction (Rule N2)

Don't pick names that commit to a specific implementation. `Modem.dial(phoneNumber)` is fine until cable modems appear, at which point the abstraction breaks. `Modem.connect(locator)` covers dial-up, cable, USB, and Bluetooth without renaming.

Same applies to repository methods, gateway interfaces, and any pluggable boundary.

## T10. Classes are nouns; methods are verbs

Classes: `Customer`, `WikiPage`, `Account`, `AddressParser`. Avoid `Manager`, `Processor`, `Data`, `Info` — see SKILL.md red list.

Methods: `postPayment`, `deletePage`, `save`. Accessors `get` / `set` / `is`.

Overloaded constructors → static factories with intent: `Complex.fromRealNumber(23.0)` is more honest than `Complex(23.0)`. Make the constructor private to enforce it.

## T11. Don't be cute

`HolyHandGrenade` is a joke for one team for one week. Rename to `deleteItems`. No slang (`whack()` → `kill()`), no culture-bound puns (`eatMyShorts()` → `abort()`). The joke ages out; the next reader doesn't share your humour.

## T12. One word per concept

Pick `get` *or* `fetch` *or* `retrieve` across the codebase — not all three. Same for `controller` / `manager` / `driver` for the same role. A consistent lexicon helps anyone reading multiple modules pick the right call without browsing headers.

## T13. Don't pun

Same word, different semantics misleads. `add` for arithmetic (concatenate two values) and `add` for "append to a collection" — the second should be `insert` or `append`. Reusing one word for two operations forces the reader into intense study instead of quick skim.

## T14. Solution / problem domain

Your readers are programmers. Use CS terms, algorithm names, pattern names, math terms when applicable: `Visitor`, `Queue`, `EventBus`, `CircuitBreaker`. They carry precise meaning the reader already knows.

When no programmer-eese exists, use the business term so a maintainer can ask a domain expert.

## T15. Add meaningful context

A bare `state` variable is ambiguous; inside an `Address` class, the same field is obvious. Group related names via classes or namespaces; prefix only as a last resort (`addrState` is OK, `Address` class is better).

Side effect: once shared variables move into a class, the original function shrinks naturally — handle the shrinking under function-design, not here.

## T16. Don't add gratuitous context

Don't prefix every class in the GSD project with `GSD…`. The IDE autocomplete punishes you with a mile of `G…` matches. Differentiate only when types actually collide: `PostalAddress`, `MacAddress`, `WebAddress`.

## House extensions

### One-word default

Default to a single domain noun. A second word must add domain meaning, not synonym noise. Three+ words is almost always a smell.

Test: drop the second word — does the domain lose meaning? If no, one word is enough.

### No negated booleans

`isEnabled`, not `isNotDisabled`. Double-negation in conditional expressions (`if (!isNotDisabled)`) is unforgivable.

### No conjunctions in class names

A class doing two things should be two classes. The conjunction is the smell. `OrderAndPaymentValidator` → `OrderValidator` + `PaymentValidator`, or a higher-level `CheckoutValidator` if such a concept exists.

### Conversion methods in pairs

Inverse operations should be named symmetrically. `toDomain()` and `fromRow()` together; never `toDomain()` and `mapBack()`. Symmetry signals the inverse relationship.
