# The smell

You're describing a textbook **Liskov Substitution Principle (LSP)** violation. `BaseController.initialize()` defines a contract: "this gets called by the framework, do whatever subclass-specific setup is needed." Your override secretly tightens that contract to "...but only inside a live JavaFX runtime with a real Scene attached." Any code that holds a `BaseController` reference (including a test harness) can no longer safely call `initialize()` — the subtype is *not* substitutable for the supertype.

Two SOLID principles are tangled here, and it helps to separate them:

1. **LSP** — your override strengthens preconditions ("a live UI must exist"). That's the contract break.
2. **SRP** — `initialize()` is mixing two responsibilities: *orchestration* (what should happen on init) and *execution against live UI* (the actual scene-graph pokes). Those have different reasons to change and different testability profiles.

The DIP/ISP angles are downstream of fixing those two.

# Recommendation: Humble Object + extracted collaborator

The cleanest fix is the **Humble Object** pattern (Meszaros, popularised by Feathers and the GOOS book). The idea: keep the part that *must* touch the framework as thin and dumb as possible — so thin it's not worth testing — and push every decision, branch, and piece of logic into a plain object you fully own.

Concretely:

```
MyController extends BaseController     ← humble; framework-bound; no logic
        │
        ▼
    MyViewModel / MyPresenter           ← plain class; all the logic; fully testable
        │
        ▼
    View interface (ports)              ← what the controller can do to the UI
```

## Refactor in three moves

**1. Define a narrow `View` port** (ISP — only the operations *this* screen needs):

```java
public interface OrderView {
    void showOrders(List<OrderRow> rows);
    void setBusy(boolean busy);
    void showError(String message);
}
```

**2. Move all logic into a presenter** that depends on the port, not on JavaFX:

```java
public final class OrderPresenter {
    private final OrderView view;
    private final OrderService service;

    public OrderPresenter(OrderView view, OrderService service) { ... }

    public void onInitialize() {
        view.setBusy(true);
        try {
            view.showOrders(service.loadInitial());
        } catch (Exception e) {
            view.showError(e.getMessage());
        } finally {
            view.setBusy(false);
        }
    }
}
```

This is the class you actually unit-test. No JavaFX, no `initialize()`, no lifecycle. Mock `OrderView` and `OrderService`, assert call order.

**3. Make the controller humble** — it implements the port and forwards lifecycle:

```java
public final class OrderController extends BaseController implements OrderView {
    @FXML private TableView<OrderRow> table;
    @FXML private ProgressIndicator spinner;

    private OrderPresenter presenter;

    @Override
    public void initialize() {
        super.initialize();                          // honour base contract
        presenter = new OrderPresenter(this, lookupService());
        presenter.onInitialize();
    }

    @Override public void showOrders(List<OrderRow> rows) { table.setItems(...); }
    @Override public void setBusy(boolean busy)          { spinner.setVisible(busy); }
    @Override public void showError(String msg)          { /* dialog */ }
}
```

The controller now contains only mechanical translations: "framework says X → call presenter / poke widget." Nothing branches, nothing decides, nothing throws in a non-framework context — because there's nothing to test there.

# Why this is the right answer (vs. alternatives)

- **"Just guard with `if (Platform.isFxApplicationThread())`"** — patches the symptom, leaves the LSP break in place, and your `initialize()` still can't be unit-tested. Reject.
- **"Override with an empty `initialize()` in tests via a test double subclass"** — works, but the controller still owns the logic, so you're testing it through the framework or through an awkward subclass. You'll keep hitting the same wall every time logic grows.
- **"Extract a `protected doInitialize()` template-method hook"** — better, but it only solves the LSP problem inside this hierarchy. Logic is still entangled with a JavaFX-derived class, so tests still need TestFX or `Platform.startup()`. Humble Object goes further: the logic class has *zero* framework on its classpath.
- **Move to MVVM with a reactive view-model** — same shape as the presenter approach, just with observable properties instead of a port interface. Pick this variant if your codebase already uses bindings; the SOLID story is identical.

# The LSP litmus test, going forward

For any override, ask: *"If I handed a caller a reference typed as the base class, could they invoke this method in any context the base class allows?"* If the answer is "only if JavaFX is running" / "only on the FX thread" / "only after `show()`" — you've added a precondition the base didn't have. That's the signal to extract a Humble Object rather than push more logic into the override.

# Bottom line

Treat the controller as **infrastructure**, not as a place where business behaviour lives. Drive everything through a plain `Presenter`/`ViewModel` against a narrow `View` port. The controller stays humble, the LSP contract stays intact, your tests stop needing a JavaFX runtime, and `BaseController` keeps its honest meaning.
