# GoF — Theory (language-agnostic)

23 patterns from Gamma, Helm, Johnson, Vlissides — *Design Patterns: Elements of Reusable Object-Oriented Software* (1994). Each entry: intent, the problem it solves, basic structure, language-agnostic example. Kotlin status lives in `kotlin.md`; Spring usage in `spring-boot.md`.

Organised by GoF's three categories: Creational (5) / Structural (7) / Behavioural (11).

---

## Creational patterns (5)

Patterns that abstract object creation, decoupling clients from the concrete classes they instantiate.

### 1. Singleton

> Ensure a class has only one instance, and provide a global point of access to it.

**Problem:** some objects must be unique across the system (config, logger, registry). Multiple instances would cause inconsistency or wasted resources.

**Structure:** private constructor, static `getInstance()` accessor, static field holding the single instance. Lazy initialisation optional.

**Anti-pattern in modern code:** Singleton is often a global, hidden dependency that breaks testability. Prefer DI in modern systems — Spring's default bean scope IS Singleton, but with explicit dependency declaration.

---

### 2. Builder

> Separate the construction of a complex object from its representation, so that the same construction process can create different representations.

**Problem:** an object with many optional fields makes the constructor unwieldy. Telescoping constructors (constructor with 2 args, with 3, with 4...) are unmaintainable.

**Structure:** a `Builder` class with fluent setters and a final `build()` method. Optionally, a `Director` that composes a particular sequence of builder calls.

**Note:** in languages with named arguments + default values (Kotlin, Python, Swift), Builder is largely subsumed.

---

### 3. Factory Method

> Define an interface for creating an object, but let subclasses decide which class to instantiate. Factory Method lets a class defer instantiation to subclasses.

**Problem:** a class needs to create instances of a related type, but the exact concrete type depends on context (the subclass).

**Structure:** an abstract method `create()` in the base class; subclasses override `create()` to return their concrete type.

**Note:** in modern code, often replaced by a static / companion factory method (`Order.create(...)`) without the inheritance machinery.

---

### 4. Abstract Factory

> Provide an interface for creating families of related or dependent objects without specifying their concrete classes.

**Problem:** you need to construct a set of related objects (e.g., for one of several "themes" or "providers"), and the family must be consistent — you don't want to mix Stripe gateway with Adyen receipts.

**Structure:** an `AbstractFactory` interface with methods returning related products (`createGateway()`, `createReceipt()`). Concrete factories implement it for each family.

---

### 5. Prototype

> Specify the kinds of objects to create using a prototypical instance, and create new objects by copying this prototype.

**Problem:** constructing a new object from scratch is expensive or complicated; copying an existing object is cheaper.

**Structure:** a `clone()` method on each class. The client clones an instance instead of constructing one.

**Note:** in Kotlin, `data class.copy()` is the language-level Prototype with no ceremony.

---

## Structural patterns (7)

Patterns concerned with composing classes and objects into larger structures.

### 6. Adapter

> Convert the interface of a class into another interface clients expect. Adapter lets classes work together that couldn't otherwise because of incompatible interfaces.

**Problem:** you need to use a class whose interface doesn't match what your client expects (legacy code, third-party SDK).

**Structure:** an `Adapter` class that implements the expected interface and translates calls to the adaptee's interface.

**Note:** in DDD, Adapter is essentially the Anti-Corruption Layer pattern (see `ddd-context-mapping`).

---

### 7. Decorator

> Attach additional responsibilities to an object dynamically. Decorators provide a flexible alternative to subclassing for extending functionality.

**Problem:** you want to add behaviour to an object (caching, logging, retry) without changing its interface or modifying its code.

**Structure:** a `Decorator` class that holds a reference to the wrapped object, implements the same interface, and adds behaviour around the delegated calls.

---

### 8. Facade

> Provide a unified interface to a set of interfaces in a subsystem. Facade defines a higher-level interface that makes the subsystem easier to use.

**Problem:** a client needs to coordinate several lower-level classes; doing so directly couples the client to all of them and bloats the client.

**Structure:** a `Facade` class that exposes a high-level operation and orchestrates the underlying subsystem internally.

**Note:** most "service" classes are Facades; the pattern is so common it's rarely named.

---

### 9. Composite

> Compose objects into tree structures to represent part-whole hierarchies. Composite lets clients treat individual objects and compositions of objects uniformly.

**Problem:** you have hierarchical structures (file systems, UI trees, organisational charts) and want to handle leaves and composites the same way.

**Structure:** a `Component` interface; `Leaf` (no children) and `Composite` (has children) both implement it. Composite delegates operations to its children recursively.

---

### 10. Bridge

> Decouple an abstraction from its implementation so that the two can vary independently.

**Problem:** you have two orthogonal axes of variation (e.g., shape × renderer, dispatcher × sender). Combining them with inheritance gives you an explosion of subclasses.

**Structure:** an `Abstraction` class holds a reference to an `Implementor` interface; concrete `Abstraction`s and concrete `Implementor`s vary independently.

---

### 11. Proxy

> Provide a surrogate or placeholder for another object to control access to it.

**Problem:** you need to add behaviour around access to an object without the object knowing — caching, lazy loading, access control, remote invocation.

**Structure:** a `Proxy` class that implements the same interface as the real object, intercepting calls before forwarding them.

**Variants:** Virtual Proxy (lazy load), Protection Proxy (access control), Remote Proxy (RPC), Smart Proxy (reference counting).

---

### 12. Flyweight

> Use sharing to support large numbers of fine-grained objects efficiently.

**Problem:** you need many instances of an object, but most state is shared and could be deduplicated.

**Structure:** an intrinsic state shared via a Flyweight pool; extrinsic state passed in as method parameters.

**Note:** rarely needed in modern garbage-collected runtimes; specific cases (very large numbers of short-lived objects) still apply.

---

## Behavioural patterns (11)

Patterns concerned with algorithms and the assignment of responsibilities between objects.

### 13. Strategy

> Define a family of algorithms, encapsulate each one, and make them interchangeable. Strategy lets the algorithm vary independently from clients that use it.

**Problem:** you have a piece of code that varies in behaviour based on context (sorting strategy, payment method, pricing rule), and the variants need to be selectable.

**Structure:** a `Strategy` interface; concrete `Strategy` implementations; a `Context` class that holds a Strategy and delegates to it.

**Note:** in languages with first-class functions (Kotlin), Strategy is just a function type.

---

### 14. Observer

> Define a one-to-many dependency between objects so that when one object changes state, all its dependents are notified and updated automatically.

**Problem:** one object's state change should trigger reactions in others, but the object shouldn't know who those others are.

**Structure:** a `Subject` (or `Observable`) maintains a list of `Observer`s; on state change, it notifies all observers.

**Note:** modern reactive streams (`Flow`, RxJava, Reactor) and event publishers (`ApplicationEventPublisher`) IS Observer, with framework support for the wiring.

---

### 15. Command

> Encapsulate a request as an object, thereby letting you parameterise clients with different requests, queue or log requests, and support undoable operations.

**Problem:** you need to treat operations as values — to queue them, log them, undo them, send them across the wire.

**Structure:** a `Command` interface with `execute()`. Concrete `Command` classes capture the request data and the target. A `Receiver` is the object the command operates on.

---

### 16. Iterator

> Provide a way to access the elements of an aggregate object sequentially without exposing its underlying representation.

**Problem:** you need to traverse a collection without the client knowing whether it's a list, tree, or generated stream.

**Structure:** an `Iterator` interface with `hasNext()` and `next()`. The aggregate exposes a method to obtain an iterator.

**Note:** built into virtually every modern language. Custom Iterator implementation is rare.

---

### 17. Template Method

> Define the skeleton of an algorithm in an operation, deferring some steps to subclasses. Template Method lets subclasses redefine certain steps of an algorithm without changing the algorithm's structure.

**Problem:** several variants of an algorithm share the same overall structure, differing only in specific steps.

**Structure:** a `final` (or non-overridable) method in the base class defines the algorithm; abstract or `open` methods are the variation points subclasses override.

**Note:** often replaced by composition + Strategy in modern code, which avoids inheritance constraints.

---

### 18. Chain of Responsibility

> Avoid coupling the sender of a request to its receiver by giving more than one object a chance to handle the request. Chain the receiving objects and pass the request along the chain until an object handles it.

**Problem:** several objects could handle a request, but the sender shouldn't know which one. Or: the request should be processed in stages, each potentially handling or passing.

**Structure:** a chain of handler objects, each holding a reference to the next. Each handler decides whether to handle or pass.

**Note:** servlet filter chains and middleware pipelines (Express, Koa) are Chain of Responsibility.

---

### 19. State

> Allow an object to alter its behaviour when its internal state changes. The object will appear to change its class.

**Problem:** an object's behaviour depends on its state, and managing state-dependent behaviour with `if/switch` chains becomes unmanageable.

**Structure:** a `State` interface with the methods that vary by state; concrete `State` classes implement them. The `Context` holds a current State and delegates.

**Note:** sealed hierarchies in modern languages collapse this into a clean form.

---

### 20. Mediator

> Define an object that encapsulates how a set of objects interact. Mediator promotes loose coupling by keeping objects from referring to each other explicitly.

**Problem:** several objects collaborate, but each knows about the others, creating an n² coupling mesh.

**Structure:** a `Mediator` class through which all collaboration flows. Colleagues only know the mediator.

**Note:** orchestrator services in modern code (e.g., a `CheckoutOrchestrator`) are Mediators. The same idea is also DDD's Application Service.

---

### 21. Memento

> Without violating encapsulation, capture and externalise an object's internal state so that the object can be restored to this state later.

**Problem:** you need undo or snapshot functionality without exposing the object's internals.

**Structure:** a `Memento` object captures the state; the originator (the object) creates and restores from mementos; a caretaker holds the mementos but doesn't inspect them.

**Note:** `data class` snapshots are the modern form.

---

### 22. Visitor

> Represent an operation to be performed on the elements of an object structure. Visitor lets you define a new operation without changing the classes of the elements on which it operates.

**Problem:** you have a stable hierarchy of types and want to add new operations on them without modifying every type. Inheritance puts each operation on each type; Visitor inverts this.

**Structure:** an `ElementVisitor` interface with `visit(ConcreteA)`, `visit(ConcreteB)`, etc. Each `Element` has an `accept(Visitor)` method that calls back the right `visit`.

**Note:** **obsolete in languages with sealed hierarchies + exhaustive `when`**. Sealed types let you add new operations as new functions over the sealed type without modifying the type, with compile-time exhaustiveness — strictly better than Visitor.

---

### 23. Interpreter

> Given a language, define a representation for its grammar along with an interpreter that uses the representation to interpret sentences in the language.

**Problem:** you have a small DSL or query language and want to parse and evaluate it.

**Structure:** an abstract syntax tree of `Expression` types (terminal and non-terminal), each with an `interpret(context)` method.

**Note:** modern systems use parser libraries or build type-safe DSLs; classical Interpreter is rare.

---

## How to think about GoF in modern Kotlin

The original 1994 catalogue was framed in C++/Smalltalk — languages with constraints that modern statically-typed functional/OO languages have eliminated. The patterns survive as *names for shapes that recur*; the *implementation* changes per language.

A useful taxonomy for Kotlin:

- **Subsumed by language features** (~11 patterns): Singleton, Strategy, Observer, Composite, Visitor, Prototype, Decorator, Iterator, State, Memento, Command. These have language-level idioms (`object`, function types, `Flow`, sealed, `data class.copy()`, `by`, `Iterable`, sealed + `when`).
- **Still apply with idiomatic forms** (~7 patterns): Adapter, Bridge, Facade, Abstract Factory, Mediator, Template Method, Interpreter. The pattern is real; the implementation is leaner than in 1994.
- **Provided by Spring** (within the above): Proxy via AOP (`@Transactional`, `@Cacheable`), Observer via `ApplicationEventPublisher`, Abstract Factory via `@Profile`, Facade/Mediator via `@Service`.

The vocabulary remains useful for *communication*: "this is a Facade", "this is a Strategy", "I'm using Decorator via `by` delegation". The names accelerate design conversations even when the implementations are one-liners.

See `kotlin.md` for the per-pattern Kotlin form, `spring-boot.md` for the Spring-provided forms, `bad-practices.md` for Java-flavoured anti-patterns to avoid, `best-practices.md` for when to use names vs when to skip them.
