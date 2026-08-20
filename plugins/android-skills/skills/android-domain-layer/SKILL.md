---
name: android-domain-layer
description: >
  Use when deciding where a piece of behaviour goes in an Android/Kotlin or KMP domain layer —
  writing or reviewing a use case / interactor, a domain model, entity, value object, or a
  `:domain` / `:core:model` module. Symptoms — a validation `if` or a total/eligibility/expiry
  calculation inside a use case; a domain `data class` with fields and no behaviour; two use
  cases computing the same thing slightly differently; `require` vs `Result` placement; a use
  case that only forwards to one repository call; a derived property invented for a screen whose
  ticket states no rule; a calculation moved onto a model while a copy stays behind; "where does
  this rule belong?".
---

# Android Domain Layer

**Business rules belong to the domain model. Business logic belongs to the use case.** Confusing the two is the most common domain-layer mistake: the rule gets written inline in the use case that happened to need it first, and every later caller either re-implements it or forgets it.

- A **business rule** is a statement that is true about a domain concept regardless of who asks or what triggered the call — *an order with no lines can't be submitted*, *a discount is 0–100%*, *a subscription is expired when its end date has passed*. It is decidable from the data the concept already holds, so it belongs **on the type that holds that data**.
- **Business logic** is the orchestration that applies rules across collaborators — fetch, combine, sequence, transact, decide what to do when a rule says no. That needs repositories, other aggregates, the clock, the network. That is the **use case**.

## The placement test

> **Can I decide this using only the data this type already holds?**
> **Yes** → a property, method, or `init` check on the model. **No** (it needs a repository, another aggregate, the current time, a remote call) → the use case.

Two corollaries worth stating, because both get violated in the same review:

- A rule that can only be tested through a mocked repository is in the wrong place. Rules are pure functions of the model — testable with no mocks, no `runTest`, no dispatcher.
- A use case that computes something a second use case also needs has stolen a rule from the model. Move it, don't copy it.

## First: is there a rule here at all?

The placement test answers *where* a rule goes. It does not conjure one, and applying it to a ticket that states no rule is its own failure mode.

A list screen, a settings toggle, a detail view that renders what the repository returned — these have no business rule, so the model stays a plain `data class` and you add nothing to it. **A derived property you had to go looking for is a requirement you invented**: `val canBecomeDefault get() = !isDefault` sitting beside the `isDefault` the model already exposes, a value class wrapped around a field nothing validates, a policy type for a screen that only lists rows.

The same restraint applies to gaps in the spec. *"The deposit is 30% for standard bookings"* says nothing about non-standard ones — return zero and raise the question; do not fill the silence with *"then the full total is due"*. An invented rule is worse than a misplaced one: a misplaced rule is at least a requirement someone asked for.

## Anemic model, fat use case — the shape to stop writing

```kotlin
// ❌ model is a bag of fields; every rule lives in whichever use case needed it first
data class Order(val lines: List<OrderLine>, val discountPercent: Int, val status: OrderStatus)

class SubmitOrderUseCase(private val orders: OrderRepository) {
    suspend operator fun invoke(order: Order): Result<OrderId> {
        if (order.lines.isEmpty()) return Result.failure(OrderError.Empty)          // rule
        if (order.discountPercent !in 0..100) return Result.failure(OrderError.BadDiscount) // rule
        val total = order.lines.sumOf { it.unitPrice * it.quantity } *              // rule
            (100 - order.discountPercent) / 100
        return orders.submit(order, total)
    }
}
```

`PreviewOrderUseCase` now needs the same total, reimplements it, rounds differently, and the checkout screen quotes a price the server rejects. Nothing in `Order` prevented an invalid `discountPercent` from existing in the first place.

```kotlin
// ✅ the rules sit on the concepts they are about
@JvmInline
value class DiscountPercent private constructor(val value: Int) {
    companion object {
        fun of(value: Int): Result<DiscountPercent> =                  // user input → Result
            if (value in 0..100) Result.success(DiscountPercent(value))
            else Result.failure(OrderError.BadDiscount)
    }
}

data class Order(
    val lines: List<OrderLine>,
    val discount: DiscountPercent,
    val status: OrderStatus,
) {
    init { require(lines.distinctBy(OrderLine::sku).size == lines.size) }  // invariant → require

    val subtotal: Money get() = lines.fold(Money.ZERO) { acc, line -> acc + line.total }
    val total: Money get() = subtotal.lessPercent(discount)
    val isSubmittable: Boolean get() = lines.isNotEmpty() && status == OrderStatus.Draft
}

class SubmitOrderUseCase(
    private val orders: OrderRepository,
    private val payments: PaymentRepository,
) {
    suspend operator fun invoke(order: Order): Result<OrderId> {
        if (!order.isSubmittable) return Result.failure(OrderError.NotSubmittable)
        // everything left needs collaborators — that is what makes it the use case's job
        return payments.charge(order.total).mapCatching { orders.submit(order) }
    }
}
```

The derived values are **properties, not constructor parameters** — the same rule the four-bucket `UiState` section of `android-skills:android-dev` applies one layer up: a constructor parameter lets a caller `copy(total = …)` into a state the rules say is impossible.

## `require` vs `Result` — invariants vs input

- **`init { require(…) }` / private constructor** — for what must *never* exist. A violation is a programmer error, and throwing is correct: `Order` with duplicate SKUs, a negative `Money`. Enforce at construction so no code downstream has to re-check.
- **`Result` / a sealed error from a factory** — for what a *user* can legitimately get wrong: a typed discount, an email, a date range from a form. The rule still lives in the domain type; only the failure mode differs. Never make the ViewModel catch an exception for ordinary bad input.

Mapping the failure to a message is UI work — the model names the violation, it does not phrase it.

## Moving a rule is a refactor, not a rewrite

Relocating a rule — out of a use case, out of a ViewModel, onto the model — has three obligations. Each is a real defect when it is skipped, and each is easy to miss because the diff reads as tidying.

- **The behaviour must be identical.** `subtotalCents * percent / 100` on `Long` truncates. Re-expressing it with `Double`, `BigDecimal`, or a rounding helper changes what real customers are charged, and nothing in the diff announces it. If you think the existing arithmetic is wrong, say so separately — never correct it silently inside a move.
- **The old call site moves with it.** Adding the rule to the model while the original expression stays where it was produces exactly the drift the move was meant to prevent. The old site must now *call* the rule.
- **The helpers travel too.** A relocated rule usually leans on constants, formatters, or small extensions that were `private` or `internal` to the file it left. Hoist them somewhere both callers reach. Copy-pasting an `internal fun money()` into the second feature is duplication whether or not you classify formatting as presentation — *"it isn't a business rule"* is a reason to keep it out of `:core:model`, never a reason to have two of it.

**And a dependency isn't placed until it's wired.** Passing `now` in means something must supply it: a `Clock` constructor parameter needs its DI binding in the same change, or the code doesn't compile. Correct placement that leaves the app unbuildable is not a win — this never comes at the cost of working code.

## Use case responsibilities — and when not to write one

A use case orchestrates and nothing else: sequence repository calls, combine sources, apply cross-aggregate rules, and act as the `Result` boundary (it catches `DataError` thrown by the repository and returns a domain error — see step 3 of the layered model in `android-skills:android-data-layer`). Conventions: one public `operator fun invoke`, `suspend` or returning `Flow`, named for the action (`SubmitOrder`, not `OrderManager`).

**Skip the use case entirely when it would only forward.** `class GetUserUseCase(repo) { suspend operator fun invoke() = repo.user() }` adds a file, a DI binding, and a test for zero behaviour — let the ViewModel depend on the repository. Add the use case when there is orchestration to own, or when the project already applies a use-case-per-action convention (match the project — `android-skills:android-dev`, *Reuse the project's existing mechanism*).

Threading is not a use-case concern: don't wrap the body in `withContext` — the repository owns its own dispatcher and the caller owns the scope (`android-skills:kotlin-coroutines`).

## What never enters the domain module

`:domain` / `:core:model` is pure Kotlin — zero Android dependencies, so it compiles in `commonMain` and in a plain JVM test.

- No `Context`, `Uri`, `Parcelable`, `@Entity`, `@Serializable`, Compose types, or Retrofit/Ktor types. DTOs and Room entities map to domain models at the data boundary; UI models map at the UI boundary.
- No repository calls inside a model method. If a rule needs to load something, it isn't a rule about that model — it's a use case that reads first, then asks the model.
- No `System.currentTimeMillis()` / `LocalDate.now()` inside a rule: pass the instant in (or inject `kotlinx.datetime.Clock`). `subscription.isExpiredAt(now)` is a testable rule; `subscription.isExpired()` reading the system clock is an untestable one.
- Keep the module's surface honest — implementations `internal`, interfaces `public` (`android-skills:modularization`).

## Reviewing for this

Grep-able smells, each meaning "a rule escaped its model": an `if` in a use case that mentions only fields of one model; `sumOf` / `filter` / date comparison over one model's own collection inside a use case; a domain `data class` whose body is empty across a feature that clearly has rules; the same expression in two use cases. A rule hidden in a file-private extension in the ViewModel's own file is still in the ViewModel — a pure function is not a placement.

The opposite smells, each meaning "a rule was invented or a move went wrong": a derived property on a model that no ticket asked for; a rule supplied for a case the spec left silent; two copies of a formatter or constant after a calculation moved; an injected dependency with no binding anywhere. Move the rule onto the model, delete the duplicate, and keep the use case's test for the orchestration only — the rule now has a mock-free test of its own.
