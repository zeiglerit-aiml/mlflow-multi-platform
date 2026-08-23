# Architecture decision record

## System definition

The platform converts a business question and governed data into a validated ML task, selects compatible heterogeneous algorithms, loads or trains MLflow artifacts, executes models, compares normalized outputs, and returns evidence suitable for deterministic clients and an LLM-generated explanation.

## Principal decisions

### Organize externally by task

Public APIs are task-first (`classification`, `regression`, `forecasting`), because scikit-learn, PyTorch, and TensorFlow are implementation frameworks. Advanced users may filter by framework or invoke an exact registered model.

### Use two interfaces over one application core

- FastAPI REST/SSE serves browsers and conventional clients.
- MCP exposes coarse-grained tools and resources to the relay LLM.
- Both call `MLOrchestrator`; business rules are never duplicated in protocol adapters.

### Separate control and data planes

MCP is the agent control interface. Model inference uses internal HTTP initially and may move to gRPC, KServe, Ray Serve, or managed cloud endpoints without changing the public contracts.

### Deploy serving pools, not every version

Logical model artifacts remain independently addressable, but compatible artifacts share a serving pool and cache. Dedicated deployments are reserved for incompatible dependencies, GPUs, large memory, latency isolation, or security boundaries.

## Component responsibilities

| Component | Owns | Does not own |
|---|---|---|
| Relay agent | Intent, tool choice, explanation | Metric calculation or promotion |
| MCP server | Agent schemas and authorized tools | Model execution logic |
| FastAPI gateway | REST contracts, jobs, SSE | Framework-specific prediction |
| Orchestrator | Planning, routing, policy | Artifact persistence |
| MLflow | Runs, metrics, signatures, artifacts, aliases, traces | API gateway traffic routing |
| Serving pool | Load/cache artifacts, transform, predict | Cross-model promotion policy |
| Comparison engine | Normalize and calculate comparisons | Natural-language claims |

## Request path

1. Validate the request envelope.
2. Formulate or confirm the ML task.
3. Inspect the dataset schema and label availability.
4. Query algorithm capabilities and registered artifacts.
5. Filter by task, schema, policy, latency, and deployment readiness.
6. Create an auditable execution plan.
7. Execute candidates in parallel.
8. Normalize results to `ModelResult`.
9. Calculate agreement/ensemble deterministically.
10. Return JSON; optionally let the relay LLM narrate it.

## Production persistence

The in-memory analysis dictionary in the starter API must be replaced with PostgreSQL and a queue/worker system before horizontal scaling. Use Pub/Sub on GCP or Service Bus on Azure for work dispatch, with managed PostgreSQL for analysis state.

## Security

- Cloud IAM for users and workloads.
- Workload Identity Federation on GKE or Microsoft Entra Workload ID on AKS.
- Secret Manager/Key Vault references rather than long-lived static credentials.
- Separate scopes for catalog read, inference, training, deployment, promotion, and deletion.
- Dataset URIs must resolve through an allowlisted connector—not arbitrary server-side URLs.
- Promotion remains approval-gated until policy maturity justifies automation.
