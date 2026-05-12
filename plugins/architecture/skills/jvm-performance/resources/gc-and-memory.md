# GC and Memory — Choice, Tuning, Diagnostics

Picking a collector. Reading GC logs. Heap dump analysis. Container sizing.

---

## 1. GC choice — at a glance

| Collector | Latency target | Throughput | Heap size sweet spot | When to use |
|---|---|---|---|---|
| **Serial** | High pauses | Low | < 100MB | Embedded only; never servers |
| **Parallel** | High throughput / batch | Highest | Any | Batch jobs, throughput > latency |
| **G1** (default since JDK 9) | 50-200ms pauses | Good | 4GB-32GB | Default OLTP service. Balanced. |
| **ZGC** | < 10ms pauses | Slightly lower than G1 | Any heap up to TB | Latency-critical, large heaps |
| **Generational ZGC** (JDK 21+) | < 1ms typical | Closer to G1 | Any | Modern default for latency-critical |
| **Shenandoah** (Red Hat) | Sub-10ms | Slightly lower than G1 | 4GB-200GB | Alternative to ZGC; OpenJDK varies |

### Default recommendation

| Service type | GC |
|---|---|
| Default Spring Boot OLTP | **G1** (just leave it) |
| Latency-critical (< 50ms p99) | **Generational ZGC** (JDK 21+) |
| Throughput batch / data pipeline | **Parallel** |
| Microservice that scales horizontally, small heap | **G1** |
| Big heap (> 32GB) regardless of workload | **ZGC** |

### Selecting

```
-XX:+UseG1GC                # default in JDK 9+; explicit for clarity
-XX:+UseZGC                 # ZGC
-XX:+UseZGC -XX:+ZGenerational    # Generational ZGC (JDK 21+)
-XX:+UseParallelGC          # Parallel (batch)
-XX:+UseShenandoahGC        # Shenandoah (if Red Hat OpenJDK)
```

---

## 2. G1 essentials

G1 (Garbage First) divides heap into regions (~1-32MB each), prefers regions with most garbage. Mostly-concurrent; pauses for evacuation.

### Useful flags

```
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200            # target — soft hint, not guarantee
-XX:G1HeapRegionSize=4M             # region size; let it auto-pick unless tuning
-XX:G1MixedGCCountTarget=8          # number of mixed GCs (default)
-XX:G1ReservePercent=15             # reserve to avoid full GC
-XX:+ParallelRefProcEnabled         # parallel weak reference processing
-XX:+UseStringDeduplication         # save heap on duplicate strings (only G1)
```

### Reading G1 GC log

Enable:
```
-Xlog:gc*:file=/var/log/gc.log:time,uptime,level,tags:filecount=10,filesize=10M
```

Sample line:
```
[2026-05-12T10:23:45.123+0000][2.345s][info][gc] GC(42) Pause Young (Normal) (G1 Evacuation Pause)
  256M->48M(2048M) 12.345ms
```

- `Pause Young (Normal)` — young collection
- `256M->48M(2048M)` — before → after (out of total heap)
- `12.345ms` — pause duration

Look for:
- **`Pause Full (G1)`** — full GC, BAD. G1 is supposed to avoid these. Investigate.
- **High pause time** > MaxGCPauseMillis target — heap pressure
- **`To-space exhausted`** — evacuation failure, often precedes full GC. Increase heap or `G1ReservePercent`.

### G1 anti-patterns

- **Heap < 4GB.** G1 overhead doesn't pay off vs Parallel.
- **`MaxGCPauseMillis=10`** — unrealistic target; G1 will thrash trying to meet it.
- **Manual `NewRatio` tuning** — G1 sizes generations adaptively; flag is ignored.

---

## 3. ZGC essentials

ZGC: concurrent, sub-millisecond pauses, scales to TB heaps. JDK 21+ generational variant adds Young Gen efficiency.

### Useful flags

```
-XX:+UseZGC
-XX:+ZGenerational                  # JDK 21+; new default in time
-Xmx16g
-XX:SoftMaxHeapSize=14g            # soft cap, allows occasional spike
-XX:+UseLargePages                  # may need OS config
-Xlog:gc*:file=/var/log/gc.log:time,uptime,level,tags
```

### Reading ZGC log

```
[1.234s][info][gc] GC(7) Garbage Collection (Allocation Rate) 1024M(50%)->512M(25%)
```

ZGC pauses are very short and rare; log lines are sparser than G1.

### When ZGC over G1

- Heap > 32GB
- p99 latency targets < 50ms and GC is in the way
- Old code with many references (G1 marking is slow)

Trade-off: ~10-20% more CPU for the concurrent work. Throughput slightly lower than G1 for small heaps.

---

## 4. Generational ZGC (JDK 21+)

Most workloads benefit. Combines ZGC's low pauses with generational efficiency (young objects collected separately, faster).

```
-XX:+UseZGC -XX:+ZGenerational
```

For new JDK 21+ Spring Boot services with latency requirements, this is often a better default than G1.

---

## 5. Memory regions in the JVM

When the container OOM-kills a JVM, heap isn't the whole story:

| Region | Set by | Notes |
|---|---|---|
| **Java heap** | `-Xmx`, `-Xms` | Visible in `jstat`, `jcmd GC.heap_info` |
| **Metaspace** | `-XX:MaxMetaspaceSize` | Class metadata; grows with classloaders |
| **Compressed class space** | `-XX:CompressedClassSpaceSize` | Compressed class pointers (if `-XX:+UseCompressedClassPointers`, default for heap < 32GB) |
| **Code cache** | `-XX:ReservedCodeCacheSize` | JIT-compiled native code; if full, JIT stops |
| **Direct buffers** | `-XX:MaxDirectMemorySize` | `ByteBuffer.allocateDirect`; used by Netty, Lettuce |
| **Thread stacks** | `-Xss512k` × number of threads | 1MB default per thread |
| **GC structures** | Implicit, per collector | ZGC needs more bookkeeping than G1 |
| **Native** | JNI / native libs | Hard to bound; use NMT |

```bash
# See what's used
jcmd <pid> VM.native_memory summary
```

### Container sizing formula

```
container memory ≈ -Xmx + (Metaspace ≈ 200M) + (Code cache ≈ 250M) + 
                          (Direct ≈ 100M-500M) + 
                          (Thread stacks ≈ #threads × 1M) + 
                          (Native ≈ 100M) + 
                          (GC overhead ≈ 5-15% of heap)
```

Rule of thumb: **container memory = `-Xmx` × 1.5 to 2**.

Always set:
```
-Xmx2g -Xms2g                          # fix heap size to avoid resize churn
-XX:MaxMetaspaceSize=256m              # bound metaspace
-XX:ReservedCodeCacheSize=256m         # ensure JIT has space
```

Or use `MaxRAMPercentage` to size heap from container limit:
```
-XX:MaxRAMPercentage=75                # 75% of container memory → heap
```

---

## 6. OutOfMemoryError types

| Error | Region | Common cause |
|---|---|---|
| `Java heap space` | Heap | Memory leak, undersized heap |
| `Metaspace` | Metaspace | Classloader leak (Hibernate proxies, web app reload) |
| `GC overhead limit exceeded` | Heap | > 98% time in GC for > 5min; usually memory exhausted |
| `Direct buffer memory` | Direct | Netty leak; unclosed `ByteBuffer.allocateDirect` |
| `unable to create new native thread` | Threads | Hit OS thread limit; thread leak |
| `Compressed class space` | CCS | Many classloaders; rare |
| `Requested array size exceeds VM limit` | N/A | Code asked for ` > 2^31 - some bytes`; bug |
| `Killed (OOM Killer)` | Container | Container exceeded limit; non-heap is the culprit |

### Always set

```
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/var/log/heap-dumps/heap-${HOSTNAME}-${timestamp}.hprof
-XX:+ExitOnOutOfMemoryError              # don't half-dead — fail fast
```

For container OOM kills (where JVM doesn't OOM), enable NMT to see what grew non-heap.

---

## 7. Heap dump analysis with Eclipse MAT

Open `heap.hprof` in MAT (Memory Analyzer Tool):

1. **Run Leak Suspects Report** (Analysis → Leak Suspects)
   - Identifies top retained dominators
   - Usually pinpoints the leak instantly

2. **Histogram** — top classes by retained size
   - `Class` column, `Retained Heap` column
   - Sort descending; look at top 10

3. **Dominator Tree** — what retains what
   - Right-click suspect → "Path to GC Roots" → why it's not collected

4. **Look at thread locals** — `ThreadLocal` leaks are a classic web-app leak

### Common leak patterns

| Pattern | Symptom |
|---|---|
| ThreadLocal not cleared | retained classloader, growing thread map |
| Static collection that only grows | `HashMap` retained from a class with static field |
| Listener not unregistered | observer pattern with orphaned listeners |
| Cache with no eviction | unbounded growth in a `ConcurrentHashMap` |
| Hibernate cache misconfig | second-level cache grows unbounded |
| ClassLoader leak in hot-reload setup | metaspace pressure, old WebApplicationContext retained |

---

## 8. GC tuning steps

```
1. Baseline: enable GC log, capture 30+ min under steady-state load
2. Analyse with GCViewer / gceasy.io:
   - Average pause time
   - Pause time distribution (p99)
   - Throughput (% of time NOT in GC)
   - Frequency of young/old/full GC
3. Identify pain:
   - Pauses too long → increase heap, or switch to ZGC
   - Pauses too frequent → tune young gen or G1 region size
   - Full GC happening → never; investigate eagerly
4. Make ONE change at a time
5. Re-test under same load; compare GC log
6. Verify in production (different traffic shape)
```

### Common safe tweaks for G1

- **Heap too small** → increase `-Xmx`. Pauses go up but full GC risk goes down.
- **Mixed GC too aggressive** → `-XX:G1MixedGCCountTarget=16` (slower old gen reclaim)
- **Humongous allocations** (objects > 50% region) → `-XX:G1HeapRegionSize=8M` (or bigger)

### What NOT to tune

- `-XX:NewRatio`, `-XX:SurvivorRatio` — G1 ignores these
- `-XX:ParallelGCThreads`, `-XX:ConcGCThreads` — usually optimal at default (= cores)
- `-XX:+UseParallelOldGC` — deprecated; obsolete

---

## 9. Thread dumps — diagnostic patterns

```bash
jcmd <pid> Thread.print > threads.txt
```

### Patterns

**Deadlock:**
```
Found one Java-level deadlock:
=============================
"Thread-A":
  waiting to lock Monitor@0x... (Object lock A)
  held by thread "Thread-B"
"Thread-B":
  waiting to lock Monitor@0x... (Object lock B)
  held by thread "Thread-A"
```
Fix: re-order lock acquisition or use timeout-based locks.

**Hung in synchronised block:**
```
"http-nio-8080-exec-15" #234 BLOCKED on java.util.HashMap@0x...
   at SomeService.process(SomeService.java:42)
"http-nio-8080-exec-20" #239 RUNNABLE
   at SomeService.process(SomeService.java:42)
   - locked java.util.HashMap@0x...
```
20+ threads BLOCKED → hot sync. Use `ConcurrentHashMap` or fine-grained locks.

**Thread starvation (pool exhaustion):**
- All `http-nio-*` threads RUNNABLE in IO read
- New requests queue (Tomcat queue grows)
- Look at downstream IO: DB, external HTTP

**Excessive thread count:**
```bash
jcmd <pid> Thread.print | grep "java.lang.Thread.State" | sort | uniq -c
```
If > 500 threads, you have thread management issues. Look for unbounded `Executors.newCachedThreadPool` or thread-per-request without limits.

---

## 10. Pitfalls

- **Tuning GC before profiling.** Almost never the right move.
- **`-Xmx` too high.** Bigger heap, longer pauses (G1/Parallel). ZGC scales but uses more CPU.
- **`-Xmx` too low.** Frequent collections, throughput dies.
- **Different `-Xmx` and `-Xms`.** Heap resize → pauses. Set them equal.
- **No GC log.** Flying blind. Cheap (~0%), enable everywhere.
- **Heap dump in production peak.** Stops JVM for seconds. Coordinate.
- **`System.gc()` calls in code.** Hints to GC are usually ignored or harmful. Remove.
- **DirectByteBuffer leaks.** No GC for direct memory; `MaxDirectMemorySize` is your only bound. Use `try-with-resources` or `Cleaner` pattern.
- **Class loader leaks.** Hot-deploy in app servers, dynamic class generation. Metaspace grows unbounded.
- **Container OOM with JVM not OOMing.** Non-heap usage exceeded container memory. Set NMT, lower `Xmx`, audit native allocations.
