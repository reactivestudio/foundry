# Profiling Tools — async-profiler, JFR, jcmd

How to capture and read a profile. Tool-by-tool with command lines and what to look for.

---

## 1. async-profiler — the workhorse

GitHub: `async-profiler/async-profiler`. Low-overhead (~1-3% for CPU mode), uses AsyncGetCallTrace + perf events. Produces flame graphs.

### Modes

| Mode | Profile target | Use |
|---|---|---|
| `cpu` (default) | CPU samples | Hot code, infinite loops, expensive functions |
| `alloc` | Object allocations | Allocation pressure, GC trigger source |
| `lock` | Lock contention | Synchronisation bottleneck |
| `wall` | Wall-clock time (incl. blocked threads) | Where time goes overall, including waits |
| `itimer` | Like CPU but works in containers without perf | Container fallback |
| `cycles` | Hardware cycles (perf) | Highest fidelity CPU on Linux |

### Invocation

Install:
```bash
# Download release
wget https://github.com/async-profiler/async-profiler/releases/download/v3.0/async-profiler-3.0-linux-x64.tar.gz
tar xzf async-profiler-3.0-linux-x64.tar.gz
```

Profile a running JVM by PID:
```bash
# CPU profile for 30 seconds, output flame graph HTML
asprof -d 30 -f /tmp/cpu.html <pid>

# Allocation profile, sample every 512KB allocated
asprof -e alloc -d 60 -f /tmp/alloc.html <pid>

# Wall clock — includes blocked threads (useful for IO-bound)
asprof -e wall -d 30 -f /tmp/wall.html <pid>

# Lock contention
asprof -e lock -d 60 -f /tmp/lock.html <pid>
```

Embed at JVM startup (continuous profiling):
```
-agentpath:/opt/async-profiler/lib/libasyncProfiler.so=start,event=cpu,file=/var/log/profile.jfr
```

### Container deployment

Add to your Docker image:
```dockerfile
FROM eclipse-temurin:21-jre-jammy
COPY --from=async-profiler-builder /opt/async-profiler /opt/async-profiler
ENV PATH=/opt/async-profiler/bin:$PATH
# In container, run: asprof -d 30 -f /tmp/cpu.html 1
```

For Kubernetes:
```bash
kubectl exec -it pod-name -- asprof -d 30 -f /tmp/cpu.html 1
kubectl cp pod-name:/tmp/cpu.html ./cpu.html
```

`1` is PID inside container; usually correct.

### Reading the flame graph

Vertical axis = call stack depth. Horizontal axis = sample frequency (NOT time).

**What to look for:**
- **Wide plateau at the top** = single function taking many samples → hot
- **Wide stack of calls leading to a plateau** = trace shows path to hotness
- **Many narrow spikes** = work is well-distributed
- **Mysterious wide region with no Kotlin/Spring code** = JIT compilation, GC, native code

**Common patterns:**

| Flame shape | Likely issue |
|---|---|
| Wide top in `Hibernate.LazyInitializer` | N+1 query |
| Wide top in `java.lang.StringBuilder.append` | String concatenation in loop |
| Wide region of `Reflection.invoke` | Reflection in hot path |
| Wide `sun.nio.ch.SocketRead0` | Network blocked (try wall profile) |
| Wide `unsafe_park` | Thread waiting (try wall + lock profile) |
| Wide GC stacks (G1Concurrent...) | Allocation pressure (do alloc profile) |
| Wide `_C2Compiler` early | JIT compiling (only at startup) |

### Tips

- **For startup profiles:** `-d 0` runs until JVM exits; combine with `-t` to stop at trigger.
- **Combine modes:** `-e cpu,alloc` captures both. Bigger output.
- **Filtering threads:** `-t threadname` to focus on one thread group.
- **For Kotlin coroutines:** the call stack is fragmented across continuations. Set `-e wall` + read top-of-stack carefully.

---

## 2. JFR — JDK Flight Recorder

Built into the JVM. Designed for **continuous low-overhead production profiling** (~1% overhead at `profile` settings).

### Continuous recording (production)

```
-XX:StartFlightRecording=settings=profile,duration=0s,filename=/var/log/jfr/cont.jfr,
                        disk=true,maxsize=500m,maxage=24h,name=continuous
```

This runs a rolling 24-hour buffer. On incident, dump the recording snapshot:

```bash
jcmd <pid> JFR.dump filename=/tmp/incident.jfr name=continuous
```

Open `incident.jfr` in **JDK Mission Control** (JMC) for analysis.

### Ad-hoc recording

```bash
# Start a 60s profile
jcmd <pid> JFR.start duration=60s filename=/tmp/run.jfr settings=profile

# Check status
jcmd <pid> JFR.check

# Dump while running
jcmd <pid> JFR.dump filename=/tmp/snapshot.jfr

# Stop
jcmd <pid> JFR.stop name=...
```

### Settings

| Setting | What | Overhead |
|---|---|---|
| `default` (free) | Method profiling + GC + I/O | ~1% |
| `profile` | Above + allocation profile, lock contention | ~2% |
| Custom `.jfc` file | Tunable | Variable |

For production: `default` or `profile`. `profile` adds allocation tracking.

### JMC views to look at first

1. **Java Application → Method Profiling**: top methods by samples. Equivalent to async-profiler CPU.
2. **Java Application → Memory → Allocations**: hotspots by allocation rate.
3. **JVM Internals → Garbage Collections**: GC frequency, pause durations.
4. **JVM Internals → Lock Instances**: contended locks.
5. **Java Application → Socket I/O**: long network reads/writes.

### When JFR over async-profiler

- **Continuous production profiling** — JFR's continuous mode is built-in
- **Multi-dimensional analysis** — JFR captures everything; you query it later
- **Container portability** — no native agent install needed
- **Lower analysis ceiling** — async-profiler flame graphs are sharper for CPU specifically

**Practical**: use **both**. JFR continuous for "what was happening at incident time"; async-profiler for sharper drill-down.

---

## 3. jcmd — Swiss army knife

Built-in. No extra agent. Many uses.

### Thread dump
```bash
jcmd <pid> Thread.print > threads.txt
```

Look for:
- `BLOCKED` threads → contention
- `WAITING` for a long time → starvation or correct waiting
- `RUNNABLE` with same stack across many threads → stuck in same code

Or use `jstack`:
```bash
jstack -l <pid> > threads.txt
```

### Heap dump (production)
```bash
jcmd <pid> GC.heap_dump /tmp/heap.hprof
```

Triggers a full GC + dumps live objects. **Stops the JVM for the duration.** Coordinate with ops.

Auto-dump on OOM:
```
-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/var/log/heap-dumps
```

### Quick heap info
```bash
jcmd <pid> GC.heap_info
```

Shows generation sizes, GC stats. No stop required.

### Class histogram (lightweight memory snapshot)
```bash
jcmd <pid> GC.class_histogram | head -30
```

Top classes by instance count and bytes. Quick check for "what's eating memory".

### Native memory tracking

Enable in JVM:
```
-XX:NativeMemoryTracking=summary
```

Query:
```bash
jcmd <pid> VM.native_memory summary
```

Shows breakdown: Java Heap, Class, Thread, Code, GC, Compiler, Internal, Other, Symbol, NMT, Native Memory Tracking, Arena Chunk, Logging, etc.

Useful when container OOM-kills the JVM but heap isn't full — non-heap usage (Direct buffers, native libs, thread stacks) is the culprit.

### Flag inspection
```bash
jcmd <pid> VM.flags                 # all flags
jcmd <pid> VM.flags -all | grep GC  # only GC-related
```

### System properties
```bash
jcmd <pid> VM.system_properties
jcmd <pid> VM.command_line          # full command-line
```

Sanity check: is the JVM running with the flags you expect?

### Compiler info
```bash
jcmd <pid> Compiler.codecache       # JIT code cache stats
jcmd <pid> Compiler.queue           # methods queued for compilation
```

If code cache is full, JIT stops compiling, performance degrades silently. Increase `-XX:ReservedCodeCacheSize`.

---

## 4. jstat — generation-by-generation GC stats

```bash
# GC stats every 1 second, 10 samples
jstat -gc <pid> 1s 10

# Output columns:
# S0C S1C S0U S1U EC EU OC OU MC MU CCSC CCSU YGC YGCT FGC FGCT GCT
```

Key columns:
- `EC/EU` — Eden capacity / used
- `OC/OU` — Old capacity / used  
- `YGC/YGCT` — Young GC count / total time
- `FGC/FGCT` — Full GC count / total time (Full GC is bad — investigate)

```bash
# Just GC summary
jstat -gcutil <pid> 1s

# Memory utilisation %
# S0  S1  E  O  M  CCS YGC YGCT FGC FGCT  GCT
```

Useful for live monitoring during load tests.

---

## 5. VisualVM — graphical, ad-hoc

For local development / one-off investigations. Connect to a running JVM, see live metrics, take heap dumps, basic profiling.

Not production-grade (overhead at "profile" mode is significant). Use async-profiler / JFR for serious work.

---

## 6. Workflow patterns

### Pattern A: Latency spike investigation

```
1. Check actuator/prometheus: GC pause time, request duration
2. Capture JFR snapshot from continuous recording → JMC
   - Look at GC pauses around incident time
   - Look at method profiling for hot methods
3. If hot CPU: async-profiler CPU 30s on production replica
4. If allocation pressure: async-profiler alloc
5. Form hypothesis: function X spike → check git log around incident
```

### Pattern B: OOM investigation

```
1. Check container logs for OOM kill or JVM OOMError
2. If JVM OOM: heap dump auto-captured (assuming HeapDumpOnOutOfMemoryError set)
3. Load heap.hprof in Eclipse MAT
4. Run "Leak Suspects Report" — usually pinpoints the dominator
5. Find retained set, identify retaining path
```

### Pattern C: Slow startup investigation

```
1. JFR 60s recording starting at JVM launch
2. Look at: JIT compilation time, class loading time, Spring init time
3. Compare to baseline (saved JFR from healthy boot)
4. Common causes:
   - Excessive Spring component scanning (narrow @ComponentScan)
   - Heavy `@PostConstruct` work (move to ApplicationRunner async)
   - Hibernate metadata processing (large schema)
   - Network connect at startup (lazy-init)
```

### Pattern D: Continuous regression detection

```
1. CI runs JMH microbenchmarks per commit
2. Store results; alert on > N% regression
3. For broader perf, run k6 / Gatling against PR build
4. Compare flame graphs of `main` vs PR (differential flame graph)
```

---

## 7. Common gotchas

- **AsyncGetCallTrace inaccuracy in some JVM versions.** If async-profiler shows weird stacks, try JFR for comparison. Modern JVMs (21+) are much better.
- **Container without perf permissions.** Add `--cap-add SYS_ADMIN` or fallback to `itimer` mode.
- **JIT warm-up corruption.** First 30s of profile shows JIT compiling hot methods; skip the initial period in benchmarks.
- **Sampling miss rate.** Default async-profiler interval is 10ms; rare hot spots may be missed. Lower interval (`-i 1ms`) for short-duration hot spots, but overhead increases.
- **Wall profile not in container without right capabilities.** May need `--cap-add=SYS_ADMIN` and `--security-opt=seccomp=unconfined`.
- **Native code in flame graph.** If a stack tops out in `[C++]` or `Unknown`, the native frame inhibits Java frame collection; this is usually OS or JNI code.
- **JFR continuous recording overhead.** At "profile" setting, ~2%. At "default", ~1%. Don't enable "everything" — too much data.
- **Heap dumps are huge.** A 2GB heap dumps to 2-4GB file. Disk space, transfer time. Strip / compress in transit.
- **Eclipse MAT memory consumption.** Loading a 10GB heap dump needs ~30GB working memory in MAT. Use a beefy analysis box.

---

## 8. Differential flame graphs

Compare before/after by subtracting samples:

```bash
# Capture baseline
asprof -d 60 -f baseline.html <pid>

# After change, capture new
asprof -d 60 -f after.html <pid>

# Or use --diff mode (modern async-profiler)
asprof -d 60 -e cpu --diff baseline.html -f diff.html <pid>
```

Differential flame graphs colour hot regions: red = grew, blue = shrunk. **The single most powerful tool for verifying a perf change.**

Pair with `methodology-verification`: don't claim "optimised" without a differential profile.
