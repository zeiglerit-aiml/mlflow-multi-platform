# Frontend and API experience

## Landing page

The default page should ask for intent rather than framework selection:

```text
What problem would you like to solve?
[ Which customers are likely to cancel next month?              ]

[ Upload data ] [ Connect approved source ] [ Use sample ]

Mode:  (x) Let the platform choose
       ( ) Compare selected algorithms
       ( ) Use an exact registered model

[ Analyze problem ]
```

## Plan review

Before training or expensive execution, show:

- interpreted task and target;
- dataset shape and quality warnings;
- selected algorithms and why;
- evaluation metrics;
- estimated cost/runtime class;
- whether existing artifacts can serve immediately;
- approval action for a new training job.

## Results

Display a comparison table, agreement, the deterministic recommended result, individual validation metrics, latency, and explanation method. Keep the relay-agent narrative beside—not instead of—the structured evidence.

## Advanced controls

Framework is an optional filter:

```text
Task       Any / Classification / Regression / Forecasting
Framework  Any / scikit-learn / XGBoost / PyTorch / TensorFlow
Algorithm  Auto / Logistic / KNN / Random Forest / XGBoost / MLP
Role       Champion / Challenger / Canary / Exact version
Strategy   Direct / Compare / Ensemble / Shadow
```

## Browser transport

- REST for creation and retrieval.
- SSE for one-way job progress and token streaming.
- WebSocket only when later workflows need sustained bidirectional events.
- Never send full large datasets through the browser; upload to governed storage and pass an opaque dataset identifier.

