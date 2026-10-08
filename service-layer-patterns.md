---
name: service-layer-patterns
description: Layer-by-layer design patterns for backend services — client wrappers, domain logic, task/queue orchestration, API boundaries, config, logging, exceptions. Use when adding a new external-system wrapper, a new processor/task type, a new provider or storage backend, a new route, or when reviewing whether code sits in the right layer.
---

# Service layer design patterns

Identify the layer you're touching, then follow its pattern.

```
API / entrypoint   →  routes, DTOs, auth, error mapping
Core / domain      →  business logic, algorithms, provider abstractions
Orchestration      →  task queues, pipelines, retries, caching
Client             →  wrappers around DBs, brokers, object storage, external APIs
Cross-cutting      →  config, logging, exceptions
```

## Quick reference

| Adding this | Use this |
|---|---|
| A wrapper for a DB / broker / bucket / third-party API | Lazy singleton + error-translating decorator |
| A swappable persistence backend | Repository — one abstract interface, N implementations |
| A workflow whose steps are fixed but one step varies | Template Method — skeleton in base, hook in subclass |
| A second provider / tenant rule / algorithm variant | Strategy + lookup table (never a growing `if/elif`) |
| A wrapper that narrows a third-party SDK | Adapter |
| An expensive repeated computation | Cache-aside |
| A call that fails transiently | Targeted retry with backoff |
| Many parallel sub-tasks | Deadline + partial success |

## API / entrypoint layer

- **Framework DI, not a container.** Use the web framework's own injection (e.g. FastAPI `Depends`) for auth and shared services; plain constructor injection everywhere else. Don't add a DI framework on top.
- **Centralized error mapping.** One decorator or middleware translates domain exceptions to HTTP responses. Individual handlers must not each write their own try/except-to-status-code logic.
- **DTOs at the boundary only.** Explicit request/response models (Pydantic or equivalent) for every external contract; lighter internal types (e.g. `TypedDict`) for pipeline payloads, so wire-format concerns don't leak inward. Keep external field naming as the contract requires even when it differs from internal style.
- **Facade over multi-step work.** If handling a request means "check cache, maybe enqueue, maybe call another service, format response," that sequence lives behind one method the route calls — not inline in the route.

## Core / domain layer

**Fixed pipeline, one varying step → Template Method.**

```python
class BaseProcessor:
    def run(self, payload):
        data = self.fetch(payload)
        result = self.get_result(data)   # the only hook subclasses touch
        self.store(result)
        self.notify(result)
        return result

    def get_result(self, data):
        raise NotImplementedError
```

New cases arrive as subclasses implementing the hook. `run()` is never edited again — if you find yourself adding a conditional to `run()` for one subclass, that condition belongs in the hook.

**Interchangeable implementations → Strategy + lookup table.**

```python
PROCESSORS = {"classify": ClassifyStrategy, "extract": ExtractStrategy}
strategy = PROCESSORS[task_type]()
```

Applies to provider variants, per-tenant rules, and algorithm modes alike. Adding a variant means adding a table entry, not a branch.

**Swappable persistence → Repository.** Define one abstract interface with the operations the domain needs, implement it per backend (SQL, document store, cache, remote API), and select the implementation from config. Domain code depends on the interface only, so the storage engine can change without touching business logic. Don't let query syntax for a specific engine appear above this layer.

**Narrowing a third-party SDK → Adapter.** Expose only the interface your domain actually needs. If swapping the underlying library would ripple past the adapter, the adapter is too thin.

## Orchestration layer

- **Registry over hardcoded strings.** Task names, queue names, and routing metadata belong in one table/config object, not as string literals at call sites.
- **Lifecycle hooks via signals/events.** Framework lifecycle events (startup, task-failure, shutdown) carry cross-cutting concerns like logging setup and metrics — don't repeat that logic in every task body.
- **Targeted retry.** Retry only on specific transient exception types (rate-limit, service-unavailable), with exponential backoff and jitter. Never `except Exception: retry`. Where a resource has regional/replica fallbacks, escalate only after repeated same-target failures — and keep "which target am I on" state thread-local, or concurrent calls will corrupt each other's failover.
- **Cache-aside.** Check cache → miss → compute → populate on success only. If the cached value points at external state (a file, a row), confirm that state still exists before trusting the hit; a surviving pointer to deleted data is the classic failure here.
- **Deadline + partial success.** Fan-out work (per-page, per-item) gets an overall deadline; return what completed instead of failing the batch because one item was slow. Cancel the stragglers explicitly.

## Client layer

One lazily-created shared connection per process, behind a typed error boundary:

```python
_client_lock = threading.Lock()

class FooClient:
    _client: FooSDK | None = None

    @classmethod
    def get_client(cls) -> FooSDK:
        if cls._client is None:              # fast path
            with _client_lock:
                if cls._client is None:      # re-check under lock
                    cls._client = FooSDK(CONFIG.FOO_URI)
                    atexit.register(cls.close)
        return cls._client

    @classmethod
    def close(cls) -> None:
        if cls._client is not None:
            cls._client.close()              # actually release the socket
            cls._client = None
```

Why: connections are expensive, so one per process serves every caller without a DI container.

- **Double-check under a lock.** A bare `if client is None: create` races under any threading — thread-pool fan-out, sync framework handlers in a worker pool. Two threads will each build a client and one leaks.
- **Never create the client at import time in a pre-forking worker.** A connection inherited across `fork()` shares a socket between processes and corrupts. Create it lazily inside the worker, e.g. as a memoized property on the task/worker object:
  ```python
  class FooTask(Task):
      _client = None

      @property
      def client(self):
          if self._client is None:
              self._client = FooClient.get_client()
          return self._client
  ```
- **Translate every error at this boundary.** Wrap methods with a decorator mapping the SDK's raw exceptions to a small local hierarchy (`FooConnectionError`, `FooNotFoundError`), raised `from original_exc`. Callers must never need to know which SDK is underneath — that's the whole point of the layer.
- **Close what you open.** A teardown hook that only nulls the reference leaks the connection; call the SDK's close/release.
- **Return resources as context managers.** Streams and cursors get `__enter__`/`__exit__` so cleanup isn't the caller's problem.
- **Multiple named configs → key the cache.** Per-region or per-tenant variants become `get_client(name)` over a dict, not a second singleton class.

## Cross-cutting

- **Config**: one settings object per environment (dev/prod/test), populated from environment variables, selected by a single environment-name switch. Pick one mechanism — plain class hierarchy or a settings library — and don't mix both in one repo.
- **Logging**: structured setup (e.g. `dictConfig`) once at startup; `logger = logging.getLogger(__name__)` per module; propagate a correlation/request ID so one request's lines can be traced end to end; keep machine-readable metrics on a separate logger from human-readable output. Never `print()`.
- **Exceptions**: a small typed hierarchy per subsystem, always raised `from original_exc`. A bare `Exception` or `ValueError` must never cross a module boundary as a stand-in for a domain error.

## Frontend (if the project has one)

- Every API call goes behind a per-resource service module; components never call `fetch` directly.
- Fetch logic reused across views becomes a custom hook.
- Reach for shared/global state only when state is genuinely shared across unrelated views.

## Matching existing code

Follow the conventions already in the file and repo you're editing, even where a neighbouring project differs. Apply the patterns above to new code; don't refactor existing code onto them, or "fix" inconsistencies across boundaries, unless that was the request.
