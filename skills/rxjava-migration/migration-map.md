# RxJava → Coroutines/Flow Operator Mapping

## Creation Operators

| RxJava | Coroutines/Flow |
|---|---|
| `Observable.just(x)` | `flowOf(x)` |
| `Observable.fromIterable(list)` | `list.asFlow()` |
| `Observable.fromCallable { }` | `flow { emit(call()) }` |
| `Observable.interval(n, unit)` | `flow { var tick = 0L; while(true) { emit(tick++); delay(n) } }` |
| `Observable.timer(n, unit)` | `flow { delay(n); emit(Unit) }` |
| `Observable.empty()` | `emptyFlow()` |
| `Observable.never()` | `flow { awaitCancellation() }` |
| `Observable.error(e)` | `flow { throw e }` |
| `Observable.defer { obs }` | `flow { emitAll(createFlow()) }` |
| `Observable.range(start, count)` | `(start until start + count).asFlow()` |

## Transforming Operators

| RxJava | Coroutines/Flow |
|---|---|
| `map { }` | `map { }` |
| `flatMap { }` | `flatMapMerge { }` (concurrent) |
| `concatMap { }` | `flatMapConcat { }` (sequential) |
| `switchMap { }` | `flatMapLatest { }` (cancel previous — dangerous for writes) |
| `scan(seed) { }` | `scan(seed) { }` |
| `buffer(count)` | `chunked(count)` |
| `cast<T>()` | `filterIsInstance<T>()` |
| `toList()` | `toList()` (terminal) |

## Filtering Operators

| RxJava | Coroutines/Flow |
|---|---|
| `filter { }` | `filter { }` |
| `take(n)` | `take(n)` |
| `skip(n)` | `drop(n)` |
| `first()` | `first()` |
| `firstOrDefault(d)` | `firstOrNull() ?: d` |
| `last()` | `last()` |
| `elementAt(n)` | `elementAtOrNull(n)` |
| `distinctUntilChanged()` | `distinctUntilChanged()` |
| `debounce(ms)` | `debounce(ms)` |
| `throttleLast(ms)` / `sample(ms)` | `sample(ms)` |
| `ignoreElements()` | `filter { false }` or suspend fun returning Unit |

## Combining Operators

| RxJava | Coroutines/Flow |
|---|---|
| `merge(a, b)` | `merge(a, b)` |
| `concat(a, b)` | `flow { emitAll(a); emitAll(b) }` |
| `zip(a, b) { }` | `a.zip(b) { }` |
| `combineLatest(a, b) { }` | `combine(a, b) { }` |
| `startWith(x)` | `onStart { emit(x) }` |
| `withLatestFrom(other) { }` | No direct equivalent — use `combine` with a flag to emit only on primary source |

## Error Handling

| RxJava | Coroutines/Flow |
|---|---|
| `onErrorReturn(x)` | `catch { emit(x) }` |
| `onErrorResumeNext(obs)` | `catch { emitAll(fallbackFlow) }` |
| `retry(n)` | `retry(n)` |
| `retryWhen { }` | `retryWhen { cause, attempt -> cause is IOException && attempt < 3 }` |
| `onErrorComplete()` | `catch { }` (swallow, complete) |

Note: In `catch` blocks, always rethrow `CancellationException`: `catch { e -> if (e is CancellationException) throw e else ... }`

## Utility Operators

| RxJava | Coroutines/Flow |
|---|---|
| `doOnNext { }` | `onEach { }` |
| `doOnError { }` | `catch { e -> doSomething(e); throw e }` |
| `doOnComplete { }` | `onCompletion { }` |
| `doOnSubscribe { }` | `onStart { }` |
| `doOnDispose { }` | `onCompletion { cause -> if (cause != null) cleanup() }` (fires on cancel and error, not normal completion) |
| `observeOn(scheduler)` | Caller's responsibility (collect on correct dispatcher) |
| `subscribeOn(scheduler)` | `flowOn(dispatcher)` |

## Hot Conversion

| RxJava | Coroutines/Flow |
|---|---|
| `publish().autoConnect()` | `shareIn(scope, SharingStarted.Eagerly)` |
| `replay(n).autoConnect()` | `shareIn(scope, SharingStarted.Eagerly, replay = n)` |
| `publish().refCount()` | `shareIn(scope, SharingStarted.WhileSubscribed())` |
| `BehaviorSubject` | `MutableStateFlow(initialValue)` or `MutableSharedFlow(replay = 1)` — ask user (see SKILL.md) |
| `PublishSubject` | `MutableSharedFlow(replay = 0)` |
| `ReplaySubject(n)` | `MutableSharedFlow(replay = n)` |
